import CoreGraphics
import CoreText
import Domain
import Foundation
import ScreenOCR
import Testing

/// Hands out one picture, as a window would.
private struct FixedImage: WindowImageProviding {
    let image: CGImage?

    func windowImage(of target: ScreenTarget) async throws -> CGImage? { image }
}

/// Draws `text` in black on white, large enough for the recognizer to read it reliably, so no picture file is bundled.
private func render(_ text: String) throws -> CGImage {
    let width = 1_400
    let height = 220
    let context = try #require(
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Helvetica" as CFString, 96, nil)
    let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    context.textPosition = CGPoint(x: 40, y: 70)
    CTLineDraw(line, context)
    return try #require(context.makeImage())
}

/// The CI image has no on-device Vision text models, so the real-model checks run on a Mac only.
let onDeviceModelsPresent = ProcessInfo.processInfo.environment["CI"] == nil

@Suite("Vision screen text recognizer")
struct VisionOCRTests {
    private let target = ScreenTarget(app: AppIdentity(processID: 1, name: "Mail", bundleID: "com.apple.mail"))

    private func recognize(_ text: String) async throws -> [String] {
        let recognizer = VisionScreenTextRecognizer(images: FixedImage(image: try render(text)))
        return try await recognizer.recognize(windowOf: target)
    }

    @Test(
        "a picture with Acme Corp is read on this Mac",
        .enabled(if: onDeviceModelsPresent, "needs Vision's text recognition, which the CI image lacks"))
    func english() async throws {
        let lines = try await recognize("Acme Corp")
        #expect(lines.contains { $0.localizedCaseInsensitiveContains("Acme Corp") })
    }

    @Test(
        "Spanish text with accents is read",
        .enabled(if: onDeviceModelsPresent, "needs Vision's text recognition, which the CI image lacks"))
    func spanish() async throws {
        let lines = try await recognize("Reunión con María González")
        let joined = lines.joined(separator: " ")
        #expect(joined.localizedCaseInsensitiveContains("Reunión"))
        #expect(joined.localizedCaseInsensitiveContains("González"))
    }

    @Test("a window with no picture gives no text")
    func noImage() async throws {
        let recognizer = VisionScreenTextRecognizer(images: FixedImage(image: nil))
        #expect(try await recognizer.recognize(windowOf: target).isEmpty)
    }

    @Test(
        "a blank picture gives no text",
        .enabled(if: onDeviceModelsPresent, "needs Vision's text recognition, which the CI image lacks"))
    func blank() async throws {
        #expect(try await recognize("").isEmpty)
    }
}
