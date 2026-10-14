import AppKit
import DesignSystem
import SnapshotTesting
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
        let column = min(Int(x * Double(image.width)), image.width - 1)
        let row = min(Int(y * Double(image.height)), image.height - 1)
        let start = (row * image.width + column) * 4
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
public func assertViewSnapshot<V: View>(
    of view: V, size: CGSize = SnapshotSupport.defaultSize, theme: Theme = .default, scheme: ColorScheme,
    named name: String, fileID: StaticString = #fileID, file: StaticString = #filePath, testName: String = #function,
    line: UInt = #line, column: UInt = #column
) {
    assertSnapshot(
        of: SnapshotSupport.nsImage(of: view, size: size, theme: theme, scheme: scheme),
        as: .image(precision: SnapshotSupport.precision, perceptualPrecision: SnapshotSupport.perceptualPrecision),
        named: name, fileID: fileID, file: file, testName: testName, line: line, column: column)
}
