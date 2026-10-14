import ApplicationServices

/// The accessibility API: `AXUIElement` calls, with their errors mapped to `AXFailure`. Reading through it needs the app
/// to be trusted for Accessibility and a real app in front, so it is covered by the manual check, not by tests.
struct LiveAXProvider: AXElementProviding {
    typealias Element = AXUIElement

    var isTrusted: Bool { AXIsProcessTrusted() }

    func systemWideElement() -> AXUIElement { AXUIElementCreateSystemWide() }

    func setMessagingTimeout(_ seconds: Float, on element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    func element(_ attribute: AXAttributeName, of element: AXUIElement) -> Result<AXUIElement, AXFailure> {
        copy(attribute, of: element).flatMap { value in
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return .failure(.noValue) }
            return .success(unsafeDowncast(value, to: AXUIElement.self))
        }
    }

    func string(_ attribute: AXAttributeName, of element: AXUIElement) -> Result<String, AXFailure> {
        copy(attribute, of: element).flatMap { value in
            if let text = value as? String { return .success(text) }
            // The address of a page is a URL, not a string.
            if CFGetTypeID(value) == CFURLGetTypeID() {
                return .success(CFURLGetString(unsafeDowncast(value, to: CFURL.self)) as String)
            }
            return .failure(.noValue)
        }
    }

    func range(_ attribute: AXAttributeName, of element: AXUIElement) -> Result<Range<Int>, AXFailure> {
        copy(attribute, of: element).flatMap { value in
            guard CFGetTypeID(value) == AXValueGetTypeID() else { return .failure(.noValue) }
            var range = CFRange()
            let axValue = unsafeDowncast(value, to: AXValue.self)
            guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
                range.location >= 0, range.length >= 0
            else { return .failure(.noValue) }
            return .success(range.location..<(range.location + range.length))
        }
    }

    private func copy(_ attribute: AXAttributeName, of element: AXUIElement) -> Result<CFTypeRef, AXFailure> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute.rawValue as CFString, &value)
        guard error == .success, let value else { return .failure(Self.failure(for: error)) }
        return .success(value)
    }

    private static func failure(for error: AXError) -> AXFailure {
        switch error {
        case .apiDisabled: .apiDisabled
        case .cannotComplete: .cannotComplete
        case .noValue: .noValue
        case .attributeUnsupported: .attributeUnsupported
        default: .other(error.rawValue)
        }
    }
}
