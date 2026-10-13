import AppKit
import DesignSystem
@_spi(Internals) import SnapshotTesting
import SwiftUI

/// Draws a view for a snapshot. Everything that could make two runs differ is fixed here: the size of the canvas, the
/// scale, the theme, the appearance, the locale, and motion, which is off. A picture then depends on the view and on
/// the machine's fonts and graphics only, and the references are recorded on the CI image for that reason.
public enum SnapshotSupport {
    /// Pixels per point in every picture, whatever screen the machine has.
    public static let scale: CGFloat = 2

    /// The canvas a view is drawn on when a test does not ask for another size, in points.
    public static let defaultSize = CGSize(width: 360, height: 280)

    /// How much two pictures may differ and still match: 99.9 % of the pixels have to match, and a pixel matches when it
    /// is within 2 % of the reference. Measured, not guessed: the same code drawn on macOS 26.6.2 and on the CI image
    /// (macOS 27.0.1) differs in a few hundredths to a tenth of a percent of the pixels, at the edges of letters. At
    /// 99.99 % five of the six pictures failed, at 99.9 % none. A view smaller than 0.1 % of its canvas could hide in
    /// that, so a gallery of small views uses a small canvas.
    static let precision: Float = 0.999
    static let perceptualPrecision: Float = 0.98

    /// `view` centered on a canvas of `size` that has the window color of `theme`, with a margin, in the appearance
    /// `scheme`.
    public static func cgImage<V: View>(
        of view: V, size: CGSize = defaultSize, theme: Theme = .default, scheme: ColorScheme
    ) -> CGImage {
        let canvas = Canvas(content: view, size: size)
            .themed(theme, override: scheme == .dark ? .dark : .light)
            .environment(\.motionEnabled, false)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.layoutDirection, .leftToRight)
            .environment(\.legibilityWeight, .regular)
            .environment(\.displayScale, scale)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = scale
        // Draw into a bitmap of our own, on the CPU, in sRGB: `ImageRenderer.cgImage` chooses its own way to draw.
        var image: CGImage?
        renderer.render { size, draw in
            let width = Int((size.width * scale).rounded())
            let height = Int((size.height * scale).rounded())
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.scaleBy(x: scale, y: scale)
            draw(context)
            image = context.makeImage()
        }
        guard let image else {
            preconditionFailure("SwiftUI drew no picture of the view.")
        }
        return image
    }

    public static func pngData<V: View>(
        of view: V, size: CGSize = defaultSize, theme: Theme = .default, scheme: ColorScheme
    ) -> Data {
        let image = cgImage(of: view, size: size, theme: theme, scheme: scheme)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            preconditionFailure("The picture cannot be written as PNG.")
        }
        return data
    }

    /// The color at a place in the picture, given as fractions of its width and height from the top left.
    public static func pixel(of image: CGImage, atX x: Double, y: Double) -> RGBAColor {
        let bytes = rgba(of: image)
        let column = min(Int(x * Double(image.width)), image.width - 1)
        let row = min(Int(y * Double(image.height)), image.height - 1)
        return color(in: bytes, width: image.width, column: column, row: row)
    }

    /// The smallest rectangle, in points from the top left, that holds every pixel within `tolerance` of `color` (the
    /// largest difference in any channel, from 0 to 1). Nil when no pixel is that close. It measures what is drawn in a
    /// color: the diameter of a dot, the thickness of a bar.
    public static func extent(of image: CGImage, matching color: RGBAColor, tolerance: Double) -> CGRect? {
        let bytes = rgba(of: image)
        var columns: ClosedRange<Int>?
        var rows: ClosedRange<Int>?
        for row in 0..<image.height {
            for column in 0..<image.width {
                let found = Self.color(in: bytes, width: image.width, column: column, row: row)
                let distance = max(
                    abs(found.red - color.red), abs(found.green - color.green), abs(found.blue - color.blue))
                guard distance <= tolerance else { continue }
                columns = columns.map { min($0.lowerBound, column)...max($0.upperBound, column) } ?? column...column
                rows = rows.map { min($0.lowerBound, row)...max($0.upperBound, row) } ?? row...row
            }
        }
        guard let columns, let rows else { return nil }
        return CGRect(
            x: Double(columns.lowerBound) / scale, y: Double(rows.lowerBound) / scale,
            width: Double(columns.count) / scale, height: Double(rows.count) / scale)
    }

    /// The bytes of a picture as red, green, blue, and alpha, four to a pixel, row after row from the top.
    private static func rgba(of image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        precondition(drawn, "The picture cannot be read.")
        return bytes
    }

    private static func color(in bytes: [UInt8], width: Int, column: Int, row: Int) -> RGBAColor {
        let start = (row * width + column) * 4
        func channel(_ offset: Int) -> Double { Double(bytes[start + offset]) / 255 }
        return RGBAColor(red: channel(0), green: channel(1), blue: channel(2), alpha: channel(3))
    }

    static func nsImage<V: View>(of view: V, size: CGSize, theme: Theme, scheme: ColorScheme) -> NSImage {
        let image = cgImage(of: view, size: size, theme: theme, scheme: scheme)
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private struct Canvas<Content: View>: View {
        @Environment(\.theme) private var theme
        let content: Content
        let size: CGSize

        var body: some View {
            content
                .padding(theme.spacing(.lg))
                .frame(width: size.width, height: size.height)
                .background(theme.swiftUIColor(.surfaceWindow))
        }
    }
}

/// Compares a picture of `view` with the reference of the same name next to the calling test file, in
/// `__Snapshots__`. A missing reference fails the test: record it with `make snapshots RECORD=1` on the CI image.
///
/// Before the picture, the environment is checked: recording writes `environment.txt` next to the references, and a run
/// on CI on another macOS or Xcode than the one that recorded fails with that reason (`SnapshotEnvironment`). When the
/// picture does not match, the reference and the difference are written beside the failed picture, in
/// `SnapshotArtifacts.folder`.
public func assertViewSnapshot<V: View>(
    of view: V, size: CGSize = SnapshotSupport.defaultSize, theme: Theme = .default, scheme: ColorScheme,
    named name: String, fileID: StaticString = #fileID, file: StaticString = #filePath, testName: String = #function,
    line: UInt = #line, column: UInt = #column
) {
    func report(_ message: String) {
        recordIssue(message, fileID: fileID, filePath: file, line: line, column: column)
    }
    SnapshotSupport.checkEnvironment(testFile: "\(file)", report: report)
    let strategy = Snapshotting<NSImage, NSImage>.image(
        precision: SnapshotSupport.precision, perceptualPrecision: SnapshotSupport.perceptualPrecision)
    let failure = verifySnapshot(
        of: SnapshotSupport.nsImage(of: view, size: size, theme: theme, scheme: scheme), as: strategy, named: name,
        fileID: fileID, file: file, testName: testName, line: line, column: column)
    guard let failure else { return }
    let saved = SnapshotSupport.saveComparison(testFile: "\(file)", testName: testName, name: name)
    report(
        saved.isEmpty ? failure : "\(failure)\n\nReference and difference: \(saved.map(\.path).joined(separator: ", "))"
    )
}

extension SnapshotSupport {
    /// The record of the references is written when they are being recorded and compared with this machine otherwise.
    /// A mismatch fails the run on CI and is a note elsewhere.
    static func checkEnvironment(
        testFile: String, environment: [String: String] = ProcessInfo.processInfo.environment,
        report: (String) -> Void
    ) {
        let url = SnapshotEnvironment.recordURL(forTestFile: testFile)
        let current = SnapshotEnvironment.current()
        if environment["SNAPSHOT_TESTING_RECORD"] == "all" {
            try? current.write(to: url)
            return
        }
        guard let problem = SnapshotEnvironment.problem(recorded: SnapshotEnvironment.read(from: url), current: current)
        else { return }
        if SnapshotEnvironment.mustMatch(environment) {
            report(problem)
        } else {
            FileHandle.standardError.write(Data("note: \(problem)\n".utf8))
        }
    }

    /// The names the library gives a reference: the test name and the picture name, each reduced to letters, digits,
    /// and dashes.
    static func saveComparison(testFile: String, testName: String, name: String) -> [URL] {
        let fileURL = URL(fileURLWithPath: testFile)
        let suite = fileURL.deletingPathExtension().lastPathComponent
        let picture = "\(sanitized(testName)).\(sanitized(name)).png"
        let reference = fileURL.deletingLastPathComponent().appendingPathComponent("__Snapshots__")
            .appendingPathComponent(suite).appendingPathComponent(picture)
        let failed = SnapshotArtifacts.folder.appendingPathComponent(suite).appendingPathComponent(picture)
        return (try? SnapshotArtifacts.saveComparison(reference: reference, failed: failed)) ?? []
    }

    private static func sanitized(_ string: String) -> String {
        string.replacingOccurrences(of: "\\W+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "^-|-$", with: "", options: .regularExpression)
    }
}
