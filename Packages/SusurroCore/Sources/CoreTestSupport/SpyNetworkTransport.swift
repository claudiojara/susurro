import Domain
import Foundation
import Synchronization

/// A transport that makes no request. It keeps the requests it was asked for and answers each with an empty reply, or
/// fails them.
public final class SpyNetworkTransport: NetworkTransport {
    private struct Failure: Error {}

    private let requests = Mutex<[URLRequest]>([])
    private let fails: Bool

    public init(failing: Bool = false) {
        fails = failing
    }

    /// The requests that were sent, in order.
    public var sent: [URLRequest] { requests.withLock { $0 } }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.withLock { $0.append(request) }
        if fails { throw Failure() }
        let url = request.url ?? URL(filePath: "/")
        return (Data(), URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
    }
}
