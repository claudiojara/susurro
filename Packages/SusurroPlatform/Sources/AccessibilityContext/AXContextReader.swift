import Domain

/// Reads the focused element of the app in front through the accessibility API and returns plain values: the handles of
/// the API stay inside the actor. It never throws; what cannot be read is left out, and a nil result means nothing could
/// be read at all. The text it reads lives in memory for its dictation and is never logged.
public actor AXContextReader: FocusedContextReader {
    /// How long an app may take to answer one read.
    static let messagingTimeout: Float = 0.25
    /// How many levels above the focused element are searched for the web area that holds the page.
    private static let webAreaSearchDepth = 12

    private let provider: any AXElementProviding
    /// The time on the injected clock that has passed since the reader was created.
    private let now: @Sendable () -> Duration
    private let budget: Duration

    /// The live reader, over the accessibility API.
    public init() {
        self.init(provider: LiveAXProvider(), clock: ContinuousClock(), budget: .seconds(1))
    }

    /// - Parameter budget: The most time one snapshot may take in all. Each read is limited to a quarter of a second, and
    ///   an app that answers slowly would otherwise hold the snapshot up for as many reads as it needs.
    init(provider: any AXElementProviding, clock: any Clock<Duration>, budget: Duration) {
        self.provider = provider
        now = Self.elapsed(on: clock)
        self.budget = budget
    }

    /// Reads a clock as the time since now. This is generic so that the clock's own instant type is known while the
    /// origin is held.
    private nonisolated static func elapsed<C: Clock<Duration>>(on clock: C) -> @Sendable () -> Duration {
        let origin = clock.now
        return { origin.duration(to: clock.now) }
    }

    public func snapshot() async -> FocusedContext? {
        guard provider.isTrusted else { return nil }
        return read(using: provider)
    }

    public func selectionSnapshot() async -> FocusedContext? {
        guard provider.isTrusted else { return nil }
        return readSelection(using: provider)
    }

    /// The selection only: the selected text, and the whole field with its range only for an app that does not give the
    /// selected text. Nothing above the focused element is read.
    private func readSelection<Provider: AXElementProviding>(using provider: Provider) -> FocusedContext? {
        let deadline = now() + budget
        let outOfTime = { [now] in now() >= deadline }
        let system = provider.systemWideElement()
        provider.setMessagingTimeout(Self.messagingTimeout, on: system)
        guard case .success(let focused) = provider.element(.focusedElement, of: system) else { return nil }
        provider.setMessagingTimeout(Self.messagingTimeout, on: focused)

        var context = FocusedContext()
        let subrole = try? provider.string(.subrole, of: focused).get()
        context.isSecure = subrole == AXAttributeName.secureFieldSubrole
        // A secure field is never asked for its text, so the text is never in memory.
        guard !context.isSecure, !outOfTime() else { return context }
        context.selectedText = try? provider.string(.selectedText, of: focused).get()
        if let selected = context.selectedText, !selected.allSatisfy(\.isWhitespace) { return context }
        context.selectedText = nil
        if !outOfTime() { context.selection = try? provider.range(.selectedTextRange, of: focused).get() }
        if context.selection?.isEmpty == false, !outOfTime() {
            context.fieldText = try? provider.string(.value, of: focused).get()
        }
        return context
    }

    private func read<Provider: AXElementProviding>(using provider: Provider) -> FocusedContext? {
        let deadline = now() + budget
        let outOfTime = { [now] in now() >= deadline }
        let system = provider.systemWideElement()
        provider.setMessagingTimeout(Self.messagingTimeout, on: system)
        guard case .success(let focused) = provider.element(.focusedElement, of: system) else { return nil }
        provider.setMessagingTimeout(Self.messagingTimeout, on: focused)

        var context = FocusedContext()
        let subrole = try? provider.string(.subrole, of: focused).get()
        context.isSecure = subrole == AXAttributeName.secureFieldSubrole
        // A secure field is never asked for its text, so the text is never in memory.
        if !context.isSecure {
            if !outOfTime() { context.fieldText = try? provider.string(.value, of: focused).get() }
            if !outOfTime() { context.selection = try? provider.range(.selectedTextRange, of: focused).get() }
            if !outOfTime() { context.selectedText = try? provider.string(.selectedText, of: focused).get() }
        }
        guard !outOfTime() else { return context }
        let window = try? provider.element(.window, of: focused).get()
        if let window {
            provider.setMessagingTimeout(Self.messagingTimeout, on: window)
            context.windowTitle = try? provider.string(.title, of: window).get()
        }
        guard !outOfTime() else { return context }
        context.url = pageAddress(from: focused, window: window, using: provider, outOfTime: outOfTime)
        return context
    }

    /// The address of the page: the `AXURL` of the web area above the focused element, or else the `AXDocument` of the
    /// window.
    private func pageAddress<Provider: AXElementProviding>(
        from focused: Provider.Element,
        window: Provider.Element?,
        using provider: Provider,
        outOfTime: () -> Bool
    ) -> String? {
        var current = focused
        for _ in 0..<Self.webAreaSearchDepth {
            guard !outOfTime() else { return nil }
            if (try? provider.string(.role, of: current).get()) == AXAttributeName.webAreaRole,
                let url = try? provider.string(.url, of: current).get()
            {
                return url
            }
            guard let parent = try? provider.element(.parent, of: current).get() else { break }
            current = parent
        }
        guard let window, !outOfTime() else { return nil }
        return try? provider.string(.document, of: window).get()
    }
}
