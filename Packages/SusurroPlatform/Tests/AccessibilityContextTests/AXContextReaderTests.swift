import CoreTestSupport
import Domain
import Testing

@testable import AccessibilityContext

@Suite("AX context reader", .timeLimit(.minutes(1)))
struct AXContextReaderTests {
    // The elements of the trees below.
    private static let field = 1
    private static let window = 2
    private static let group = 3
    private static let webArea = 4

    private func reader(_ tree: FakeAXTree, clock: any Clock<Duration> = SteppedClock(), budget: Duration = .seconds(1))
        -> AXContextReader
    {
        AXContextReader(provider: tree, clock: clock, budget: budget)
    }

    /// A text field in a window, as Notes has it: the focused element, its text, its cursor, and its window.
    private func notesTree() -> FakeAXTree {
        let tree = FakeAXTree()
        tree.set(FakeAXTree.system, [.focusedElement: .element(Self.field)])
        tree.set(
            Self.field,
            [
                .role: .string("AXTextArea"),
                .value: .string("hello world"),
                .selectedTextRange: .range(6..<11),
                .selectedText: .string("world"),
                .window: .element(Self.window),
                .parent: .failure(.noValue),
            ])
        tree.set(Self.window, [.title: .string("Shopping list")])
        return tree
    }

    @Test("it reads the value, the selected range, the selected text, and the title of the window")
    func readsTheField() async {
        let context = await reader(notesTree()).snapshot()

        #expect(
            context
                == FocusedContext(
                    windowTitle: "Shopping list", url: nil, isSecure: false, fieldText: "hello world",
                    selection: 6..<11, selectedText: "world"))
    }

    @Test("the selection read asks for the selected text only: not the field, the window, or the page")
    func selectionReadIsLight() async {
        let tree = notesTree()

        let context = await reader(tree).selectionSnapshot()

        #expect(context == FocusedContext(selectedText: "world"))
        let asked = Set(tree.reads.map(\.attribute))
        #expect(!asked.contains(.value))
        #expect(!asked.contains(.window))
        #expect(!asked.contains(.title))
        #expect(!asked.contains(.parent))
    }

    @Test("an app that gives no selected text has the field and the range read, for the slice")
    func selectionReadFallsBackToTheRange() async {
        let tree = notesTree()
        tree.set(
            Self.field,
            [
                .role: .string("AXTextArea"), .value: .string("hello world"), .selectedTextRange: .range(6..<11),
                .selectedText: .failure(.noValue), .window: .element(Self.window),
            ])

        let context = await reader(tree).selectionSnapshot()

        #expect(context == FocusedContext(fieldText: "hello world", selection: 6..<11))
        #expect(!tree.reads.map(\.attribute).contains(.window))
    }

    @Test("the selection read of a secure field never asks for its text")
    func selectionReadOfASecureField() async {
        let tree = notesTree()
        tree.set(
            Self.field,
            [
                .role: .string("AXTextField"), .subrole: .string("AXSecureTextField"),
                .value: .string("hunter2"), .selectedText: .string("hunter2"),
            ])

        let context = await reader(tree).selectionSnapshot()

        #expect(context == FocusedContext(isSecure: true))
        let asked = Set(tree.reads.map(\.attribute))
        #expect(!asked.contains(.value))
        #expect(!asked.contains(.selectedText))
    }

    @Test("a secure field is flagged and its text, range, and selection are never asked for")
    func secureField() async {
        let tree = notesTree()
        tree.set(
            Self.field,
            [
                .role: .string("AXTextField"), .subrole: .string("AXSecureTextField"),
                .value: .string("hunter2"), .window: .element(Self.window),
            ])

        let context = await reader(tree).snapshot()

        #expect(context?.isSecure == true)
        #expect(context?.fieldText == nil)
        #expect(context?.selection == nil)
        #expect(context?.selectedText == nil)
        #expect(context?.windowTitle == "Shopping list")
        let asked = Set(tree.reads.map(\.attribute))
        #expect(asked.isDisjoint(with: [.value, .selectedText, .selectedTextRange]))
    }

    // MARK: Browsers

    /// A page in a browser: the focused field sits in a group inside the web area, which holds the address.
    private func browserTree(documentOnWindow: Bool = false) -> FakeAXTree {
        let tree = FakeAXTree()
        tree.set(FakeAXTree.system, [.focusedElement: .element(Self.field)])
        tree.set(
            Self.field,
            [
                .role: .string("AXTextField"), .value: .string("search"), .selectedTextRange: .range(0..<0),
                .window: .element(Self.window), .parent: .element(Self.group),
            ])
        tree.set(Self.group, [.role: .string("AXGroup"), .parent: .element(Self.webArea)])
        if documentOnWindow {
            tree.set(
                Self.webArea, [.role: .string("AXWebArea"), .url: .failure(.noValue), .parent: .failure(.noValue)])
            tree.set(Self.window, [.title: .string("Inbox"), .document: .string("https://mail.google.com/mail/u/0/")])
        } else {
            tree.set(
                Self.webArea,
                [
                    .role: .string("AXWebArea"), .url: .string("https://mail.google.com/mail/u/0/#inbox"),
                    .parent: .failure(.noValue),
                ])
            tree.set(Self.window, [.title: .string("Inbox")])
        }
        return tree
    }

    @Test("the address of the page is the AXURL of the web area above the focused element")
    func webAreaAddress() async {
        let context = await reader(browserTree()).snapshot()

        #expect(context?.url == "https://mail.google.com/mail/u/0/#inbox")
        #expect(context?.windowTitle == "Inbox")
    }

    @Test("without an address on the web area, the AXDocument of the window is used")
    func documentAddress() async {
        let context = await reader(browserTree(documentOnWindow: true)).snapshot()

        #expect(context?.url == "https://mail.google.com/mail/u/0/")
    }

    // MARK: Timeout and failures

    @Test("a messaging timeout of a quarter of a second is applied to the system, the field, and the window")
    func messagingTimeout() async {
        let tree = notesTree()

        _ = await reader(tree).snapshot()

        let elements = Set(tree.timeouts.map(\.element))
        #expect(elements == [FakeAXTree.system, Self.field, Self.window])
        #expect(tree.timeouts.allSatisfy { $0.seconds == 0.25 })
    }

    @Test("without Accessibility trust nothing is read")
    func untrusted() async {
        let tree = FakeAXTree(trusted: false)

        let context = await reader(tree).snapshot()

        #expect(context == nil)
        #expect(tree.reads.isEmpty)
    }

    @Test(
        "when the focused element cannot be read there is no snapshot, and no failure",
        arguments: [AXFailure.apiDisabled, .cannotComplete, .noValue, .attributeUnsupported, .other(-25_200)])
    func focusedElementFails(failure: AXFailure) async {
        let tree = FakeAXTree()
        tree.set(FakeAXTree.system, [.focusedElement: .failure(failure)])

        #expect(await reader(tree).snapshot() == nil)
    }

    @Test(
        "an attribute that cannot be read is left out and the rest is kept",
        arguments: [AXFailure.apiDisabled, .cannotComplete, .noValue, .attributeUnsupported, .other(-25_200)])
    func attributeFails(failure: AXFailure) async {
        let tree = notesTree()
        tree.set(
            Self.field,
            [
                .value: .failure(failure), .selectedTextRange: .failure(failure), .selectedText: .failure(failure),
                .window: .element(Self.window), .parent: .failure(failure),
            ])

        let context = await reader(tree).snapshot()

        #expect(context == FocusedContext(windowTitle: "Shopping list"))
    }

    @Test("an app that exposes no attributes at all gives an empty snapshot")
    func electronApp() async {
        let tree = FakeAXTree()
        tree.set(FakeAXTree.system, [.focusedElement: .element(Self.field)])
        tree.set(Self.field, [:])

        let context = await reader(tree).snapshot()

        #expect(context == FocusedContext())
    }

    @Test("a snapshot that runs out of time stops asking and keeps what it has")
    func budgetRunsOut() async {
        let clock = SteppedClock()
        let tree = FakeAXTree(clock: clock, readCost: .milliseconds(400))
        tree.set(FakeAXTree.system, [.focusedElement: .element(Self.field)])
        tree.set(
            Self.field,
            [
                .role: .string("AXTextField"), .value: .string("hello"), .selectedTextRange: .range(0..<0),
                .selectedText: .string(""), .window: .element(Self.window), .parent: .element(Self.group),
            ])
        tree.set(Self.window, [.title: .string("Late")])

        let context = await reader(tree, clock: clock, budget: .seconds(1)).snapshot()

        // The focused element (400 ms), the subrole (800 ms), the value (1200 ms): then the budget is spent.
        #expect(context?.fieldText == "hello")
        #expect(context?.selection == nil)
        #expect(context?.windowTitle == nil)
        #expect(tree.reads.count == 3)
    }
}
