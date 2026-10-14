import CoreGraphics
import Domain
import Vision

/// Where the picture of a window comes from. A seam, so the recognizer is tested with a picture made in the test and the
/// live source (ScreenCaptureKit, which needs the Screen Recording permission) is left to the manual check.
public protocol WindowImageProviding: Sendable {
    /// The picture of the frontmost window of `app`, or nil when it has none to give.
    func windowImage(of app: AppIdentity) async throws -> CGImage?
}

/// Reads the text of a window with Vision, on this Mac and offline. The picture is dropped as soon as the text is read,
/// and the text is returned to the caller and kept nowhere.
public struct VisionScreenTextRecognizer: ScreenTextRecognizer {
    /// Spanish and English, the languages the app is used in.
    static let languages = ["es-ES", "en-US"]

    private let images: any WindowImageProviding

    public init(images: any WindowImageProviding) {
        self.images = images
    }

    public func recognize(windowOf app: AppIdentity) async throws -> [String] {
        guard let image = try await images.windowImage(of: app) else { return [] }
        try Task.checkCancellation()
        return try await Task.detached(priority: .utility) { try Self.lines(in: image) }.value
    }

    private static func lines(in image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
