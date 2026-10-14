import CoreTestSupport
import Domain
import Testing

@testable import TextShaping

@Suite("Context assembler")
struct ContextAssemblerTests {
    private let assembler = ContextAssembler()

    private static let notes = AppIdentity(processID: 1, name: "Notes", bundleID: "com.apple.Notes")
    private static let safari = AppIdentity(processID: 2, name: "Safari", bundleID: "com.apple.Safari")
    private static let slack = AppIdentity(processID: 3, name: "Slack", bundleID: "com.tinyspeck.slackmacgap")

    private static let field = FocusedContext(
        windowTitle: "Draft",
        url: "https://mail.google.com/mail/u/0/#inbox",
        fieldText: "hello world",
        selection: 6..<11,
        selectedText: "world")

    @Test("the text around the cursor and the selection are taken, bounded")
    func fieldText() {
        let context = assembler.assemble(app: Self.notes, focused: Self.field, useAppContext: true)

        #expect(context.beforeCursor == "hello ")
        #expect(context.afterCursor == "")
        #expect(context.selection == "world")
        #expect(context.windowTitle == "Draft")
        #expect(context.app == Self.notes)
        #expect(!context.isSecureField)
    }

    @Test("a secure field gives empty text, the flag set, and nothing else from the field")
    func secureField() {
        var focused = Self.field
        focused.isSecure = true

        let context = assembler.assemble(app: Self.safari, focused: focused, useAppContext: true)

        #expect(context.isSecureField)
        #expect(context.beforeCursor.isEmpty)
        #expect(context.afterCursor.isEmpty)
        #expect(context.selection.isEmpty)
        #expect(context.app == Self.safari)
    }

    @Test("with app context off the text is empty and the app, title, and address stay")
    func toggleOff() {
        let context = assembler.assemble(app: Self.safari, focused: Self.field, useAppContext: false)

        #expect(context.beforeCursor.isEmpty)
        #expect(context.afterCursor.isEmpty)
        #expect(context.selection.isEmpty)
        #expect(context.app?.bundleID == "com.apple.Safari")
        #expect(context.windowTitle == "Draft")
        #expect(context.url == "https://mail.google.com/mail/u/0/#inbox")
    }

    @Test("a secure field is flagged even when app context is off")
    func secureFlagWithToggleOff() {
        let context = assembler.assemble(
            app: Self.safari, focused: FocusedContext(isSecure: true), useAppContext: false)

        #expect(context.isSecureField)
    }

    @Test("the address is kept for a known browser only")
    func urlOnlyForBrowsers() {
        let browser = assembler.assemble(app: Self.safari, focused: Self.field, useAppContext: true)
        let notBrowser = assembler.assemble(app: Self.notes, focused: Self.field, useAppContext: true)

        #expect(browser.url == "https://mail.google.com/mail/u/0/#inbox")
        #expect(notBrowser.url == nil)
    }

    @Test("an app that exposes no text attributes gives the app and bundle ID only")
    func electronApp() {
        let context = assembler.assemble(app: Self.slack, focused: FocusedContext(), useAppContext: true)

        #expect(context == DictationContext(app: Self.slack))
        #expect(context.app?.bundleID == "com.tinyspeck.slackmacgap")
    }

    @Test("when nothing could be read the context holds the app and never fails")
    func untrusted() {
        let context = assembler.assemble(app: Self.notes, focused: nil, useAppContext: true)

        #expect(context == DictationContext(app: Self.notes))
    }

    @Test("with no app and nothing read the context is empty")
    func nothingAtAll() {
        #expect(assembler.assemble(app: nil, focused: nil, useAppContext: true) == .empty(app: nil))
    }

    @Test("a context can be read from the reader and the setting at capture time")
    func capture() async {
        let settings = Settings(useAppContext: true)
        let capture = ContextCapture(
            reader: StaticReader(Self.field), assembler: assembler, useAppContext: { settings.value })

        let withContext = await capture.capture(app: Self.notes)
        settings.value = false
        let withoutContext = await capture.capture(app: Self.notes)

        #expect(withContext.selection == "world")
        #expect(withoutContext.selection.isEmpty)
    }

    @Test("the host of the page is what may be kept of the address")
    func urlHost() {
        let context = DictationContext(app: Self.safari, url: "https://WWW.Mail.Google.com/mail/u/0/#inbox")

        #expect(context.urlHost == "mail.google.com")
        #expect(DictationContext(app: Self.safari).urlHost == nil)
    }

    @Test("the context is never encoded: it holds the text of a field")
    func notCodable() {
        #expect(!(DictationContext.self is any Encodable.Type))
        #expect(!(FocusedContext.self is any Encodable.Type))
    }

    private final class Settings: @unchecked Sendable {
        var value: Bool
        init(useAppContext: Bool) { value = useAppContext }
    }

    private struct StaticReader: FocusedContextReader {
        let focused: FocusedContext?
        init(_ focused: FocusedContext?) { self.focused = focused }
        func snapshot() async -> FocusedContext? { focused }
    }
}
