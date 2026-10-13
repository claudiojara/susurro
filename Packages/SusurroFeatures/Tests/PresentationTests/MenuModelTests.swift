import CoreTestSupport
import Domain
import Synchronization
import Testing

@testable import Presentation

@MainActor
@Suite("Menu model", .timeLimit(.minutes(1)))
struct MenuModelTests {
    /// A permissions checker whose statuses the test changes, as the user does in System Settings.
    private final class StatusBoard: PermissionsChecker {
        private let state = Mutex((statuses: [Permission: PermissionStatus](), reads: 0))

        init(_ statuses: [Permission: PermissionStatus]) {
            state.withLock { $0.statuses = statuses }
        }

        var reads: Int { state.withLock { $0.reads } }

        func set(_ permission: Permission, to status: PermissionStatus) {
            state.withLock { $0.statuses[permission] = status }
        }

        func status(_ permission: Permission) async -> PermissionStatus {
            state.withLock { state in
                state.reads += 1
                return state.statuses[permission] ?? .notDetermined
            }
        }

        func request(_ permission: Permission) async {}
    }

    private func makeModel(
        _ board: StatusBoard,
        openSettings: @escaping @MainActor (Permission) -> Void = { _ in },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }
    ) -> MenuModel {
        MenuModel(permissions: board, openSettings: openSettings, refreshInterval: .seconds(2), sleep: sleep)
    }

    @Test("before anything is read the menu shows nothing as allowed and the model as preparing")
    func initialContent() {
        let model = makeModel(StatusBoard([:]))

        #expect(
            model.content
                == MenuContent.make(
                    microphone: .notDetermined, accessibility: .notDetermined, readiness: .loading(progress: 0)))
    }

    @Test("refresh reads both statuses")
    func refreshReadsStatuses() async {
        let model = makeModel(StatusBoard([.microphone: .granted, .accessibility: .denied]))

        await model.refresh()

        #expect(model.content.microphone.isGranted)
        #expect(!model.content.accessibility.isGranted)
    }

    @Test("a permission granted in System Settings shows after the next refresh, without a relaunch")
    func grantShowsAfterRefresh() async {
        let board = StatusBoard([.microphone: .granted, .accessibility: .denied])
        let model = makeModel(board)
        await model.refresh()
        let before = model.content.accessibility

        board.set(.accessibility, to: .granted)
        await model.refresh()

        #expect(!before.isGranted)
        #expect(model.content.accessibility.isGranted)
        #expect(model.content.accessibility.title == "Accessibility: allowed")
    }

    @Test("a permission revoked while the app runs shows after the next refresh")
    func revocationShowsAfterRefresh() async {
        let board = StatusBoard([.microphone: .granted, .accessibility: .granted])
        let model = makeModel(board)
        await model.refresh()

        board.set(.microphone, to: .denied)
        await model.refresh()

        #expect(!model.content.microphone.isGranted)
        #expect(model.content.accessibility.isGranted)
    }

    @Test("the model line follows the readiness the recognizer reports, until the stream ends")
    func observesReadiness() async {
        let model = makeModel(StatusBoard([:]))
        let (readiness, continuation) = AsyncStream.makeStream(of: RecognizerReadiness.self)
        let observing = Task { await model.observe(readiness) }

        continuation.yield(.loading(progress: 0.3))
        while model.content.modelLine != "Speech model: preparing… 30%" { await Task.yield() }
        continuation.yield(.ready)
        while model.content.modelLine != "Speech model: ready" { await Task.yield() }
        continuation.finish()
        await observing.value

        #expect(model.content.modelLine == "Speech model: ready")
    }

    @Test("a refresh keeps the model line the recognizer reported")
    func refreshKeepsTheModelLine() async {
        let model = makeModel(StatusBoard([.microphone: .granted]))
        let (readiness, continuation) = AsyncStream.makeStream(of: RecognizerReadiness.self)
        continuation.yield(.ready)
        continuation.finish()
        await model.observe(readiness)

        await model.refresh()

        #expect(model.content.modelLine == "Speech model: ready")
        #expect(model.content.microphone.isGranted)
    }

    @Test("keepRefreshing reads the statuses, waits the interval, and goes on until the wait is cancelled")
    func keepsRefreshing() async {
        let board = StatusBoard([.microphone: .granted])
        let waits = Mutex<[Duration]>([])
        let model = makeModel(
            board,
            sleep: { duration in
                let count = waits.withLock { waits in
                    waits.append(duration)
                    return waits.count
                }
                if count == 3 { throw CancellationError() }
            })

        await model.keepRefreshing()

        #expect(board.reads == 6)  // two statuses, three times
        #expect(waits.withLock { $0 } == [.seconds(2), .seconds(2), .seconds(2)])
    }

    @Test("opening System Settings passes the permission on")
    func opensSettings() {
        var opened: [Permission] = []
        let model = makeModel(StatusBoard([:]), openSettings: { opened.append($0) })

        model.openSettings(for: .accessibility)
        model.openSettings(for: .microphone)

        #expect(opened == [.accessibility, .microphone])
    }
}
