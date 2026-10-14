import Foundation
import Network
import Synchronization

/// A request exactly as it arrived on the socket, so a check can read every byte that a cloud service would receive.
public struct CapturedRequest: Sendable {
    /// `POST /v1/messages HTTP/1.1`.
    public let requestLine: String
    /// The headers in the order they were sent, with the case they were sent in.
    public let headers: [(name: String, value: String)]
    public let body: Data

    /// The head and the body as one text, for a check that something is found nowhere in the request.
    public var rawText: String {
        let head = ([requestLine] + headers.map { "\($0.name): \($0.value)" }).joined(separator: "\r\n")
        return head + "\r\n\r\n" + String(decoding: body, as: UTF8.self)
    }

    public var headerNames: [String] { headers.map(\.name) }

    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// A web server on a port of this Mac: `127.0.0.1`, a port the system picked, and a real TCP connection from a real
/// `URLSession`. It records every request as it came off the wire and answers each with one fixed reply. It stands in for
/// a local proxy in the checks that look at what leaves the app. Unlike `StubServer` it goes through the network stack, so
/// only an opt-in check uses it.
public final class LoopbackServer: Sendable {
    private struct State {
        var requests: [CapturedRequest] = []
    }

    private final class Shared: Sendable {
        let state = Mutex(State())
        let reply: Data
        let status: Int

        init(reply: String, status: Int) {
            self.reply = Data(reply.utf8)
            self.status = status
        }
    }

    public let port: UInt16
    private let shared: Shared
    private let listener: NWListener

    /// Starts listening, and returns once the port is known.
    public static func start(reply: String, status: Int = 200) async throws -> LoopbackServer {
        let shared = Shared(reply: reply, status: status)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "susurro.loopback-server")
        listener.newConnectionHandler = { connection in
            Connection(connection: connection, shared: shared).start(on: queue)
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = Mutex(false)
            listener.stateUpdateHandler = { state in
                let finish: (Result<UInt16, any Error>) -> Void = { result in
                    let first = resumed.withLock { done in
                        defer { done = true }
                        return !done
                    }
                    if first { continuation.resume(with: result) }
                }
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue { finish(.success(port)) }
                case .failed(let error): finish(.failure(error))
                case .cancelled: finish(.failure(CancellationError()))
                default: break
                }
            }
            listener.start(queue: queue)
        }
        return LoopbackServer(port: port, shared: shared, listener: listener)
    }

    private init(port: UInt16, shared: Shared, listener: NWListener) {
        self.port = port
        self.shared = shared
        self.listener = listener
    }

    deinit {
        listener.cancel()
    }

    public func url(_ path: String = "/") -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    public var requests: [CapturedRequest] { shared.state.withLock { $0.requests } }

    /// One connection: reads a request until its body is whole, records it, answers, and closes.
    private final class Connection: @unchecked Sendable {
        private let connection: NWConnection
        private let shared: Shared
        private var buffer = Data()

        init(connection: NWConnection, shared: Shared) {
            self.connection = connection
            self.shared = shared
        }

        func start(on queue: DispatchQueue) {
            connection.start(queue: queue)
            receive()
        }

        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, isComplete, error in
                if let data { buffer.append(data) }
                if let request = parsed() {
                    shared.state.withLock { $0.requests.append(request) }
                    respond()
                } else if isComplete || error != nil {
                    connection.cancel()
                } else {
                    receive()
                }
            }
        }

        /// The request once its head and its whole body are in the buffer.
        private func parsed() -> CapturedRequest? {
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
            let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
            var lines = head.components(separatedBy: "\r\n")
            let requestLine = lines.removeFirst()
            let headers = lines.compactMap { line -> (name: String, value: String)? in
                guard let colon = line.firstIndex(of: ":") else { return nil }
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                return (String(line[..<colon]), value)
            }
            let length =
                headers.first { $0.name.caseInsensitiveCompare("Content-Length") == .orderedSame }
                .flatMap { Int($0.value) } ?? 0
            let body = buffer[end.upperBound...]
            guard body.count >= length else { return nil }
            return CapturedRequest(requestLine: requestLine, headers: headers, body: Data(body.prefix(length)))
        }

        private func respond() {
            let head =
                "HTTP/1.1 \(shared.status) OK\r\nContent-Type: application/json\r\nContent-Length: \(shared.reply.count)\r\nConnection: close\r\n\r\n"
            connection.send(
                content: Data(head.utf8) + shared.reply, contentContext: .finalMessage, isComplete: true,
                completion: .contentProcessed { [connection] _ in connection.cancel() })
        }
    }
}
