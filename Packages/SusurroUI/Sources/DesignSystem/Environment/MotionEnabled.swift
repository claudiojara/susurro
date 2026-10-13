import SwiftUI

extension EnvironmentValues {
    /// Whether views animate. It is on unless something above turns it off. Snapshot tests turn it off so that a view
    /// is drawn in its end state, and the same picture comes out every time.
    @Entry public var motionEnabled: Bool = true
}
