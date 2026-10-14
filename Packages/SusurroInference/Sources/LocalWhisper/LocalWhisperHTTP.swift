import Domain
import Foundation

/// A `multipart/form-data` body: text fields and one file.
struct MultipartForm: Sendable {
    let boundary: String
    private(set) var body = Data()

    init(boundary: String = "susurro-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }

    mutating func addFile(_ name: String, filename: String, contentType: String, data: Data) {
        append(
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n"
        )
        body.append(data)
        append("\r\n")
    }

    /// Closes the body, and returns it.
    mutating func finish() -> Data {
        append("--\(boundary)--\r\n")
        return body
    }

    private mutating func append(_ text: String) {
        body.append(Data(text.utf8))
    }
}

/// Refuses a redirect that leaves this Mac, so that a server on this Mac cannot pass the audio on.
private final class LoopbackRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let isAllowed: @Sendable (URL) -> Bool

    init(isAllowed: @escaping @Sendable (URL) -> Bool) {
        self.isAllowed = isAllowed
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(isAllowed) == true ? request : nil)
    }
}

/// Sends the audio to a Whisper server that the user runs on this Mac, and reads the transcript from its answer.
///
/// Two kinds of server are spoken to. An OpenAI-compatible one (`/v1/audio/transcriptions`) gets the file, the model,
/// the language, and the vocabulary as the prompt. A `whisper.cpp` server (`/inference`) gets the file, the language, and
/// the vocabulary as the prompt, and no model, which it has loaded already. Both answer `{"text": "..."}`.
///
/// The address must be on this Mac. It is checked where the request is made, and a redirect to another host is refused.
struct LocalWhisperHTTP: Sendable {
    let endpoint: URL
    let style: LocalWhisperServerStyle
    let model: String
    let timeout: Duration
    private let session: URLSession
    private let isAllowed: @Sendable (URL) -> Bool

    /// - Parameters:
    ///   - isAllowed: Whether an address may be sent audio. The rule is `LoopbackEndpoint`; a test passes its own to
    ///     reach a stub, and one test checks the rule itself.
    init(
        endpoint: URL, style: LocalWhisperServerStyle, model: String, timeout: Duration = .seconds(60),
        session: URLSession = .shared,
        isAllowed: @escaping @Sendable (URL) -> Bool = { LoopbackEndpoint.validated($0.absoluteString) != nil }
    ) throws {
        guard isAllowed(endpoint) else { throw LocalWhisperError.invalidEndpoint }
        self.endpoint = endpoint
        self.style = style
        self.model = model
        self.timeout = timeout
        self.session = session
        self.isAllowed = isAllowed
    }

    func transcribe(_ clip: AudioClip, options: RecognitionOptions) async throws -> String {
        var form = MultipartForm()
        form.addFile("file", filename: "audio.wav", contentType: "audio/wav", data: clip.wavData())
        if style == .openAICompatible, !model.isEmpty { form.addField("model", model) }
        if let language = options.language { form.addField("language", language) }
        if !options.vocabulary.isEmpty { form.addField("prompt", options.vocabulary.joined(separator: ", ")) }
        form.addField("response_format", "json")
        form.addField("temperature", "0")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Double(timeout.components.seconds)
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finish()

        let data = try await send(request)
        struct Answer: Decodable { let text: String }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { throw LocalWhisperError.response }
        return answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether something answers at the address. Any answer counts, an error status included: a server that only takes
    /// a POST answers a GET with one. Nothing but a connection is needed, and no audio is sent.
    func isReachable() async -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        do {
            let (_, response) = try await session.data(for: request, delegate: redirects)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }

    private var redirects: LoopbackRedirects { LoopbackRedirects(isAllowed: isAllowed) }

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request, delegate: redirects)
            guard let http = response as? HTTPURLResponse else { throw LocalWhisperError.response }
            guard (200..<300).contains(http.statusCode) else { throw LocalWhisperError.http(http.statusCode) }
            return data
        } catch let error as LocalWhisperError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw LocalWhisperError.timedOut
            default: throw LocalWhisperError.network
            }
        } catch {
            throw LocalWhisperError.network
        }
    }
}
