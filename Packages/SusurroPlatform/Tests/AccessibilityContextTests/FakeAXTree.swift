import CoreTestSupport
import Synchronization

@testable import AccessibilityContext

/// An accessibility tree that a test builds: elements are numbers, and each has attributes that give a value or fail.
/// It records every read, so a test can show what was not asked for.
final class FakeAXTree: AXElementProviding {
    typealias Element = Int

    enum Attribute {
        case string(String)
        case element(Int)
        case range(Range<Int>)
        case failure(AXFailure)
    }

    struct Read: Equatable {
        let attribute: AXAttributeName
        let element: Int
    }

    /// The system-wide element.
    static let system = 0

    private struct State {
        var nodes: [Int: [AXAttributeName: Attribute]] = [:]
        var reads: [Read] = []
        var timeouts: [(element: Int, seconds: Float)] = []
        var cost: Duration = .zero
    }

    private let state = Mutex(State())
    private let clock: SteppedClock?
    let isTrusted: Bool

    /// - Parameters:
    ///   - clock: When set, every read moves it by `readCost`, as reads of a slow app do.
    init(trusted: Bool = true, clock: SteppedClock? = nil, readCost: Duration = .zero) {
        isTrusted = trusted
        self.clock = clock
        state.withLock { $0.cost = readCost }
    }

    func set(_ node: Int, _ attributes: [AXAttributeName: Attribute]) {
        state.withLock { $0.nodes[node] = attributes }
    }

    var reads: [Read] { state.withLock { $0.reads } }
    var timeouts: [(element: Int, seconds: Float)] { state.withLock { $0.timeouts } }

    func systemWideElement() -> Int { Self.system }

    func setMessagingTimeout(_ seconds: Float, on element: Int) {
        state.withLock { $0.timeouts.append((element, seconds)) }
    }

    func element(_ attribute: AXAttributeName, of element: Int) -> Result<Int, AXFailure> {
        switch lookup(attribute, of: element) {
        case .element(let found): .success(found)
        case .failure(let failure): .failure(failure)
        default: .failure(.attributeUnsupported)
        }
    }

    func string(_ attribute: AXAttributeName, of element: Int) -> Result<String, AXFailure> {
        switch lookup(attribute, of: element) {
        case .string(let text): .success(text)
        case .failure(let failure): .failure(failure)
        default: .failure(.attributeUnsupported)
        }
    }

    func range(_ attribute: AXAttributeName, of element: Int) -> Result<Range<Int>, AXFailure> {
        switch lookup(attribute, of: element) {
        case .range(let range): .success(range)
        case .failure(let failure): .failure(failure)
        default: .failure(.attributeUnsupported)
        }
    }

    private func lookup(_ attribute: AXAttributeName, of element: Int) -> Attribute {
        let (found, cost) = state.withLock { state -> (Attribute, Duration) in
            state.reads.append(Read(attribute: attribute, element: element))
            return (state.nodes[element]?[attribute] ?? .failure(.attributeUnsupported), state.cost)
        }
        clock?.advance(by: cost)
        return found
    }
}
