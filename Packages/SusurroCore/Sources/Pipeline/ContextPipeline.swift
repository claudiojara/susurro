import Domain
import TextShaping

/// The context of a dictation and the style chosen from it.
public struct ResolvedContext: Sendable, Equatable {
    /// The context, which lives in memory for its dictation only.
    public let context: DictationContext
    public let style: StyleProfile

    public init(context: DictationContext, style: StyleProfile) {
        self.context = context
        self.style = style
    }

    /// Stamps what may be kept of the dictation on its history record: the app, the host of the page, and the style.
    public func stamped(_ record: DictationRecord) -> DictationRecord {
        var record = record
        record.applyStyle(of: context, style: style)
        return record
    }
}

/// What the coordinator needs to capture the context of a dictation and to choose its style. The context is requested as
/// the key goes down, never delays the recording, and is waited for only a short while after the key comes up.
public struct ContextPipeline: Sendable {
    /// The style settings that apply to an app and page: the tone of each category, and the overrides that could match.
    public typealias StyleSettingsProvider = @Sendable (_ bundleID: String?, _ url: String?) -> StyleSettings

    let source: any ContextSource
    let resolver: StyleResolver
    let styleSettings: StyleSettingsProvider
    let onResolved: @Sendable (ResolvedContext) -> Void

    /// - Parameters:
    ///   - styleSettings: Reads the user's style settings for an app and page when the style is resolved.
    ///   - onResolved: Receives each dictation's context and style as soon as they are resolved. The consumer must keep the
    ///     context to its dictation: it is never stored or logged. `ResolvedContext.stamped(_:)` is what may be kept.
    public init(
        source: any ContextSource,
        resolver: StyleResolver = StyleResolver(),
        styleSettings: @escaping StyleSettingsProvider = { _, _ in .default },
        onResolved: @escaping @Sendable (ResolvedContext) -> Void = { _ in }
    ) {
        self.source = source
        self.resolver = resolver
        self.styleSettings = styleSettings
        self.onResolved = onResolved
    }
}

/// The capture of one dictation's context, which starts as the key goes down. It belongs to that dictation alone, so a
/// context that arrives after the dictation was cancelled or replaced by a newer one has nobody to be handed to.
struct ContextJob: Sendable {
    private let app: AppIdentity?
    private let pipeline: ContextPipeline
    private let task: Task<DictationContext, Never>

    /// Starts capturing at a low priority and returns at once.
    init(app: AppIdentity?, pipeline: ContextPipeline) {
        self.app = app
        self.pipeline = pipeline
        task = Task(priority: .utility) { [source = pipeline.source] in await source.capture(app: app) }
    }

    /// Drops the capture. A source that ignores the cancellation still finishes, and its context is not used.
    func cancel() {
        task.cancel()
    }

    /// Waits for the context at most `deadline`, then chooses the style. A context that is late is replaced by an empty
    /// one that holds the app, which is known from the start, so the style still follows the app.
    func resolve(
        deadline: Duration, sleep: @escaping @Sendable (Duration) async throws -> Void
    ) async -> ResolvedContext? {
        let captured: DictationContext
        do {
            let task = task
            captured = try await withDeadline(deadline, stage: .transcription, sleep: sleep) { await task.value }
        } catch is CancellationError {
            return nil
        } catch {
            captured = .empty(app: app)
        }
        guard !Task.isCancelled, !task.isCancelled else { return nil }
        let style = pipeline.resolver.resolve(
            bundleID: captured.app?.bundleID, url: captured.url,
            settings: pipeline.styleSettings(captured.app?.bundleID, captured.url))
        let resolved = ResolvedContext(context: captured, style: style)
        pipeline.onResolved(resolved)
        return resolved
    }

    /// The diagnostics line for a resolved style: names of a category, a tone, and a rule, and nothing of the context.
    static func event(for resolved: ResolvedContext) -> DiagnosticEvent {
        .styleResolved(
            category: resolved.style.category.rawValue, tone: resolved.style.tone.rawValue,
            source: resolved.style.source.rawValue)
    }
}
