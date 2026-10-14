import Synchronization

/// One session that was prepared ahead of a request, kept until the next call takes it. A session is used by one call
/// only, so a dictation never sees the one before it: `take` hands the session over and empties the slot.
final class WarmSlot<Session: Sendable>: Sendable {
    private struct Held {
        let session: Session
        let instructions: String
    }

    private let held = Mutex<Held?>(nil)

    /// Keeps `session`, which was prepared with `instructions`. A session already waiting is dropped.
    func store(_ session: Session, instructions: String) {
        held.withLock { $0 = Held(session: session, instructions: instructions) }
    }

    /// The session prepared with these instructions, if there is one. The slot is empty afterward: a session prepared
    /// with other instructions is of no use to this call and is dropped too.
    func take(instructions: String) -> Session? {
        held.withLock { held in
            defer { held = nil }
            guard let current = held, current.instructions == instructions else { return nil }
            return current.session
        }
    }
}
