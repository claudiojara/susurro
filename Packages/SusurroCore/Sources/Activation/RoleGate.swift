import Domain

/// Keeps the two hotkeys apart before their events reach the `ActivationMachine`, which knows one key only. A press
/// belongs to the role whose key went down; while it is held, or while the recording it started goes on, the events of
/// the other role are dropped, so a command key that is let go can never finish a dictation hold, and the other way
/// round. Esc always goes through. A pure value, so the rules are tested without a keyboard.
///
/// One case needs the coordinator: a press of the other role while the machine waits for a second tap. The window is
/// closed first (the machine gets `doubleTapTimeout`) and the press then starts a press of its own.
public struct RoleGate: Sendable, Equatable {
    public enum Decision: Sendable, Equatable {
        /// Hand the event to the machine.
        case admit
        /// The event belongs to the other role: it goes nowhere.
        case drop
        /// End the double-tap window of the other role, then hand the event to the machine.
        case closeWindowThenAdmit
    }

    /// The role whose key is down now, if any.
    public private(set) var held: HotkeyRole?
    /// The role of the last press that started from rest, which owns what the machine is doing.
    public private(set) var owner: HotkeyRole?

    public init() {}

    /// Decides what happens to `event`, given the phase the machine is in.
    public mutating func decide(_ event: HotkeyEvent, phase: ActivationMachine.State.Phase) -> Decision {
        switch event {
        case .escape:
            return .admit
        case .down(_, let role):
            if let held, held != role { return .drop }
            if phase == .idle || owner == role {
                take(role)
                return .admit
            }
            guard case .awaitingSecondTap = phase else { return .drop }
            take(role)
            return .closeWindowThenAdmit
        case .up(_, let role):
            guard held == role else { return .drop }
            held = nil
            return .admit
        }
    }

    private mutating func take(_ role: HotkeyRole) {
        held = role
        owner = role
    }
}
