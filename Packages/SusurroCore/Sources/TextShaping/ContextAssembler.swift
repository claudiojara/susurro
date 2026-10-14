import Domain

/// Turns what the accessibility API gave into the context of a dictation. It is pure policy and never throws: whatever is
/// missing is left empty, so an app that exposes nothing still gives its name.
public struct ContextAssembler: Sendable {
    private let browsers: BrowserCatalog

    public init(browsers: BrowserCatalog = .standard) {
        self.browsers = browsers
    }

    /// - Parameters:
    ///   - app: The app that was in front as the dictation began.
    ///   - focused: What was read from the focused element, or nil when nothing could be read: Accessibility is not
    ///     trusted, or the app did not answer in time.
    ///   - useAppContext: The "use app context" setting. When off, the text around the cursor and the selection are not
    ///     taken, and the app, the window title, and the page address are.
    public func assemble(app: AppIdentity?, focused: FocusedContext?, useAppContext: Bool) -> DictationContext {
        let isSecure = focused?.isSecure ?? false
        var text = BoundedFieldText.empty
        // A secure field gives no text, whatever the setting says.
        if let focused, useAppContext, !isSecure {
            text = ContextBounds.bound(
                fieldText: focused.fieldText, selection: focused.selection, selectedText: focused.selectedText)
        }
        return DictationContext(
            app: app,
            windowTitle: focused?.windowTitle,
            // The address of a page is read for a browser. Another app's document address would say nothing about the page.
            url: browsers.isBrowser(app?.bundleID) ? focused?.url : nil,
            beforeCursor: text.before,
            afterCursor: text.after,
            selection: text.selection,
            isSecureField: isSecure)
    }
}

/// Reads the focused element and assembles the context of a dictation. This is the `ContextSource` of the app.
public struct ContextCapture: ContextSource {
    private let reader: any FocusedContextReader
    private let assembler: ContextAssembler
    private let useAppContext: @Sendable () -> Bool

    /// - Parameter useAppContext: Reads the "use app context" setting each time a context is captured, so a change
    ///   applies to the next dictation.
    public init(
        reader: any FocusedContextReader,
        assembler: ContextAssembler = ContextAssembler(),
        useAppContext: @escaping @Sendable () -> Bool
    ) {
        self.reader = reader
        self.assembler = assembler
        self.useAppContext = useAppContext
    }

    public func capture(app: AppIdentity?) async -> DictationContext {
        let focused = await reader.snapshot()
        return assembler.assemble(app: app, focused: focused, useAppContext: useAppContext())
    }
}
