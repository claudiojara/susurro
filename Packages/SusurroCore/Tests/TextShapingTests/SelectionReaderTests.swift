import Domain
import Testing
import TextShaping

@Suite("Selection reader")
struct SelectionReaderTests {
    @Test("the selected text the app gives is the selection")
    func selectedText() {
        let snapshot = FocusedContext(fieldText: "Hello there, friend", selection: 0..<5, selectedText: "Hello")

        #expect(SelectionReader.capture(from: snapshot) == .text("Hello"))
    }

    @Test("an app that gives the field and the range but not the selected text has the range cut out of the field")
    func rangeSlice() {
        let snapshot = FocusedContext(fieldText: "Hola señor, ¿qué tal?", selection: 12..<21)

        #expect(SelectionReader.capture(from: snapshot) == .text("¿qué tal?"))
    }

    @Test("the range counts UTF-16 units, as the accessibility API does")
    func utf16Range() {
        let snapshot = FocusedContext(fieldText: "👋 hi there", selection: 3..<5)

        #expect(SelectionReader.capture(from: snapshot) == .text("hi"))
    }

    @Test("a cursor with nothing selected, or a selection of blanks, is no selection")
    func none() {
        #expect(SelectionReader.capture(from: FocusedContext(fieldText: "Hello", selection: 2..<2)) == .none)
        #expect(SelectionReader.capture(from: FocusedContext(selectedText: "  \n ")) == .none)
        #expect(SelectionReader.capture(from: FocusedContext()) == .none)
    }

    @Test("a range outside the field is no selection")
    func rangeOutOfBounds() {
        #expect(SelectionReader.capture(from: FocusedContext(fieldText: "Hi", selection: 1..<9)) == .none)
    }

    @Test("a password field is never read")
    func secure() {
        let snapshot = FocusedContext(isSecure: true, fieldText: "hunter2", selection: 0..<7, selectedText: "hunter2")

        #expect(SelectionReader.capture(from: snapshot) == .secure)
    }

    @Test("nothing read at all is an unreadable selection")
    func unreadable() {
        #expect(SelectionReader.capture(from: nil) == .unreadable)
    }

    @Test("a selection up to the cap is taken, one character more is refused")
    func bounds() {
        let atCap = String(repeating: "a", count: CommandLimits.maxSelection)

        #expect(SelectionReader.capture(from: FocusedContext(selectedText: atCap)) == .text(atCap))
        #expect(SelectionReader.capture(from: FocusedContext(selectedText: atCap + "a")) == .tooLong)
    }

    @Test("two selections are the same when only their spacing differs")
    func sameSelection() {
        #expect(SelectionReader.isSame("Hello  there\n", "Hello there"))
        #expect(!SelectionReader.isSame("Hello there", "Hello world"))
        #expect(!SelectionReader.isSame("Hello", ""))
    }
}
