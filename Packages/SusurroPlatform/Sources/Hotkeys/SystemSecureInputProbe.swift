import Carbon.HIToolbox
import Domain

/// Asks the system whether Secure Event Input is on, as it is while a password field has the focus.
struct SystemSecureInputProbe: SecureInputProbe {
    func isActive() -> Bool {
        IsSecureEventInputEnabled()
    }
}
