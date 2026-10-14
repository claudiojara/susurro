import Foundation

/// An app that was running when something was captured.
public struct AppIdentity: Sendable, Equatable {
    public let processID: Int32
    public let name: String
    public let bundleID: String?

    public init(processID: Int32, name: String, bundleID: String?) {
        self.processID = processID
        self.name = name
        self.bundleID = bundleID
    }
}

/// The app in front. It is read when a dictation starts, so the text goes only to the app it was dictated in.
@MainActor
public protocol FrontmostAppProvider: Sendable {
    func current() -> AppIdentity?
}

/// The host of a page address, as it is compared and kept: lower case, without a leading `www.`.
public enum URLHost {
    /// Nil when the address has no host. An address without a scheme, such as `mail.google.com/inbox`, reads as if it
    /// had one.
    public static func of(_ url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URL(string: withScheme)?.host(percentEncoded: false), !host.isEmpty else { return nil }
        return normalized(host)
    }

    /// A host as it is compared: lower case, without `www.`.
    public static func normalized(_ host: String) -> String {
        let lowered = host.lowercased()
        return lowered.hasPrefix("www.") ? String(lowered.dropFirst(4)) : lowered
    }
}

/// What the accessibility API gave about the focused element and its window, as it was read: nothing is bounded or
/// filtered yet. A property the app does not expose is nil, so an app with no text attributes gives an empty one.
/// It lives in memory for one dictation and is never stored or logged.
public struct FocusedContext: Sendable, Equatable {
    public var windowTitle: String?
    /// The address of the page, as the web area or the window document gives it.
    public var url: String?
    /// The focused element is a secure text field, such as a password field.
    public var isSecure: Bool
    /// The whole text of the focused field.
    public var fieldText: String?
    /// The selection or cursor in `fieldText`, in UTF-16 units. A cursor is a selection of length zero.
    public var selection: Range<Int>?
    /// The selected text, for an app that gives it without giving the field.
    public var selectedText: String?

    public init(
        windowTitle: String? = nil,
        url: String? = nil,
        isSecure: Bool = false,
        fieldText: String? = nil,
        selection: Range<Int>? = nil,
        selectedText: String? = nil
    ) {
        self.windowTitle = windowTitle
        self.url = url
        self.isSecure = isSecure
        self.fieldText = fieldText
        self.selection = selection
        self.selectedText = selectedText
    }
}

/// Reads the focused element of the app in front. It never throws: what it cannot read is left out, and a nil result
/// means nothing could be read at all.
public protocol FocusedContextReader: Sendable {
    func snapshot() async -> FocusedContext?
}

/// Everything the pipeline knows about where the text goes, for one dictation: the app, the page, and the text around the
/// cursor, bounded. The field text, the selection, and the text around the cursor live in memory for their dictation and
/// are never stored or logged, which is why this type is not `Codable`. What may be kept is stamped on a
/// `DictationRecord` by `DictationRecord.applyStyle(of:style:)`.
public struct DictationContext: Sendable, Equatable {
    public let app: AppIdentity?
    public let windowTitle: String?
    /// The address of the page, for a browser only.
    public let url: String?
    /// At most 500 characters before the cursor, the nearest ones.
    public let beforeCursor: String
    /// At most 500 characters after the cursor, the nearest ones.
    public let afterCursor: String
    /// At most 1000 characters of the selection.
    public let selection: String
    /// The focused element is a secure text field: no text was read, and no OCR may be run.
    public let isSecureField: Bool

    public init(
        app: AppIdentity?,
        windowTitle: String? = nil,
        url: String? = nil,
        beforeCursor: String = "",
        afterCursor: String = "",
        selection: String = "",
        isSecureField: Bool = false
    ) {
        self.app = app
        self.windowTitle = windowTitle
        self.url = url
        self.beforeCursor = beforeCursor
        self.afterCursor = afterCursor
        self.selection = selection
        self.isSecureField = isSecureField
    }

    /// Only the app: what a dictation has when nothing else could be read in time.
    public static func empty(app: AppIdentity?) -> DictationContext {
        DictationContext(app: app)
    }

    /// The host of the page, which may be kept.
    public var urlHost: String? { url.flatMap(URLHost.of) }
}

/// Produces the context of a dictation. A source may take long; the pipeline stops waiting for it.
public protocol ContextSource: Sendable {
    func capture(app: AppIdentity?) async -> DictationContext
}

/// The settings that control what context is captured.
public enum ContextSettings {
    /// Whether the text around the cursor and the selection are read ("use app context"). When off, only the app, the
    /// window title, and the page address are captured.
    public static let useAppContext = SettingKey<Bool>(area: "context", name: "useAppContext", default: true)
}

extension DictationRecord {
    /// Stamps the only part of a dictation's context that may be kept with it: the app, the host of the page, and the
    /// style that was chosen. It copies no field text, selection, or OCR text, and a test checks that it cannot.
    public mutating func applyStyle(of context: DictationContext, style: StyleProfile) {
        bundleID = context.app?.bundleID
        appName = context.app?.name
        urlHost = context.urlHost
        category = style.category.rawValue
        tone = style.tone.rawValue
        styleSource = style.source.rawValue
    }
}
