import Foundation

/// Why a request to a cloud service gave no answer. The reason is a fixed word: it never holds the body of the
/// response or anything that was sent, because either can quote what the user said or a key.
enum CloudRequestFailure: Error, Equatable {
    case http(Int)
    case timeout
    case network
    case response

    /// The word the log and the error text use.
    var reason: String {
        switch self {
        case .http(let status): "http-\(status)"
        case .timeout: "timeout"
        case .network: "network"
        case .response: "response"
        }
    }
}

enum CloudHTTP {
    /// Sends the request and returns the body of a successful answer. A cancelled task throws `CancellationError` and
    /// cancels the request under way, and every other failure is one of `CloudRequestFailure`.
    static func send(_ request: URLRequest, using session: URLSession) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CloudRequestFailure.response }
            guard (200..<300).contains(http.statusCode) else { throw CloudRequestFailure.http(http.statusCode) }
            return data
        } catch let failure as CloudRequestFailure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw CloudRequestFailure.timeout
            default: throw CloudRequestFailure.network
            }
        } catch {
            throw CloudRequestFailure.network
        }
    }
}
