import Domain
import Testing

@testable import Presentation

@Suite("Overlay timing")
struct OverlayTimingTests {
    private let timing = OverlayTiming.standard

    @Test("an error stays longer than a success")
    func errorOutlastsSuccess() {
        #expect(timing.error > timing.inserted)
    }

    @Test("a notice is long enough to read and shorter than an error")
    func noticeBetween() {
        #expect(timing.notice > timing.inserted)
        #expect(timing.notice < timing.error)
    }

    @Test("only inserted, notice, and error states dismiss themselves")
    func whichStatesDismiss() {
        #expect(timing.dwell(for: .inserted) == timing.inserted)
        #expect(timing.dwell(for: .notice(.capReached)) == timing.notice)
        #expect(timing.dwell(for: .error(.microphoneNotGranted)) == timing.error)
        let others: [PipelineState] = [.idle, .starting, .recording(.hold), .transcribing(progress: nil)]
        #expect(others.map { timing.dwell(for: $0) } == [nil, nil, nil, nil])
    }
}
