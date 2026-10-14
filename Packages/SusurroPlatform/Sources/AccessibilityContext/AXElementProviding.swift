/// Why an accessibility read gave nothing. The reader treats every one of them the same way: what it could not read is
/// left out of the snapshot.
enum AXFailure: Error, Equatable {
    /// Accessibility is not allowed for the app.
    case apiDisabled
    /// The app did not answer in time, or cannot be reached.
    case cannotComplete
    /// The attribute exists and has no value.
    case noValue
    /// The element does not have the attribute.
    case attributeUnsupported
    /// Any other error, by its code.
    case other(Int32)
}

/// The attributes the reader asks for. The raw values are the names the accessibility API uses.
enum AXAttributeName: String {
    case focusedElement = "AXFocusedUIElement"
    case parent = "AXParent"
    case window = "AXWindow"
    case role = "AXRole"
    case subrole = "AXSubrole"
    case value = "AXValue"
    case selectedText = "AXSelectedText"
    case selectedTextRange = "AXSelectedTextRange"
    case title = "AXTitle"
    case url = "AXURL"
    case document = "AXDocument"
}

extension AXAttributeName {
    /// The role of the web area that holds a page, whose address is its `AXURL`.
    static let webAreaRole = "AXWebArea"
    /// The subrole of a password field.
    static let secureFieldSubrole = "AXSecureTextField"
}

/// The accessibility API as the reader needs it. The live provider wraps `AXUIElement` calls; tests stand in with a tree
/// of fake elements. An element is meant to stay inside the call that obtained it, so it need not be `Sendable`.
protocol AXElementProviding: Sendable {
    associatedtype Element

    /// Whether the app is trusted for Accessibility. Without it every read fails.
    var isTrusted: Bool { get }
    func systemWideElement() -> Element
    /// Limits how long a read on the element may wait for the app to answer.
    func setMessagingTimeout(_ seconds: Float, on element: Element)
    func element(_ attribute: AXAttributeName, of element: Element) -> Result<Element, AXFailure>
    func string(_ attribute: AXAttributeName, of element: Element) -> Result<String, AXFailure>
    /// A range of characters in UTF-16 units, such as the selection.
    func range(_ attribute: AXAttributeName, of element: Element) -> Result<Range<Int>, AXFailure>
}
