import Foundation
import Synchronization

/// A request as the stub server saw it.
public struct RecordedRequest: Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data

    public var bodyText: String { String(decoding: body, as: UTF8.self) }
    public var query: [URLQueryItem] { URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// What the stub answers to a request.
public enum StubReply: Sendable {
    case json(String, status: Int = 200)
    case body(Data, status: Int = 200)
    /// The request fails with this error, as a dead network or a timeout does.
    case failure(URLError.Code)
    /// The request never gets an answer, until it is cancelled.
    case hang
}

/// A web server that lives in the test process: a `URLSession` whose requests to one made-up host are answered by the
/// test, so no test reaches a network. Every server has a host of its own, so tests that run at once do not meet.
public final class StubServer: Sendable {
    private struct State {
        var requests: [RecordedRequest] = []
        var reply = StubReply.json("{}")
        var stopped = 0
    }

    public let host: String
    public let session: URLSession
    private let state = Mutex(State())

    public init(reply: StubReply = .json("{}")) {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        self.host = host
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        state.withLock { $0.reply = reply }
        StubURLProtocol.register(host: host, server: self)
    }

    deinit {
        StubURLProtocol.unregister(host: host)
        session.invalidateAndCancel()
    }

    public func url(_ path: String = "/", scheme: String = "https") -> URL {
        URL(string: "\(scheme)://\(host)\(path)")!
    }

    public func setReply(_ reply: StubReply) {
        state.withLock { $0.reply = reply }
    }

    public var requests: [RecordedRequest] { state.withLock { $0.requests } }
    /// How many requests were cancelled or finished loading, which is how a cancelled one shows.
    public var stoppedCount: Int { state.withLock { $0.stopped } }

    func record(_ request: RecordedRequest) -> StubReply {
        state.withLock { state in
            state.requests.append(request)
            return state.reply
        }
    }

    func stopped() {
        state.withLock { $0.stopped += 1 }
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private final class Weak: @unchecked Sendable {
        weak var server: StubServer?
        init(_ server: StubServer) { self.server = server }
    }

    private static let servers = Mutex<[String: Weak]>([:])

    static func register(host: String, server: StubServer) {
        servers.withLock { $0[host] = Weak(server) }
    }

    static func unregister(host: String) {
        servers.withLock { $0[host] = nil }
    }

    private static func server(for host: String) -> StubServer? {
        servers.withLock { $0[host]?.server }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host, let server = Self.server(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let recorded = RecordedRequest(
            url: url, method: request.httpMethod ?? "GET", headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request))
        switch server.record(recorded) {
        case .json(let text, let status): respond(url: url, status: status, data: Data(text.utf8))
        case .body(let data, let status): respond(url: url, status: status, data: data)
        case .failure(let code): client?.urlProtocol(self, didFailWithError: URLError(code))
        case .hang: break
        }
    }

    override func stopLoading() {
        guard let host = request.url?.host, let server = Self.server(for: host) else { return }
        server.stopped()
    }

    private func respond(url: URL, status: Int, data: Data) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// The body of a request. A request that goes through a session carries its body as a stream.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
