import Testing

@testable import TextShaping

@Suite("Context bounds")
struct ContextBoundsTests {
    /// 5000 characters, each one different from its neighbours so that the nearest ones can be told.
    private static let long = String((0..<5_000).map { Character(UnicodeScalar(UInt8(97 + $0 % 26))) })

    private func bound(_ text: String, cursor: Int, length: Int = 0) -> BoundedFieldText {
        ContextBounds.bound(fieldText: text, selection: cursor..<(cursor + length), selectedText: nil)
    }

    @Test("a 5000-character field with the cursor in the middle gives at most 500 characters each side, the nearest")
    func middleOfALongField() {
        let result = bound(Self.long, cursor: 2_500)

        #expect(result.before.count == 500)
        #expect(result.after.count == 500)
        #expect(result.before == String(Self.long.dropFirst(2_000).prefix(500)))
        #expect(result.after == String(Self.long.dropFirst(2_500).prefix(500)))
        #expect(result.selection.isEmpty)
    }

    @Test("the selection is cut to 1000 characters and leaves the text around it alone")
    func longSelection() {
        let result = bound(Self.long, cursor: 1_000, length: 3_000)

        #expect(result.selection.count == 1_000)
        #expect(result.selection == String(Self.long.dropFirst(1_000).prefix(1_000)))
        #expect(result.before == String(Self.long.dropFirst(500).prefix(500)))
        #expect(result.after == String(Self.long.dropFirst(4_000).prefix(500)))
    }

    @Test("a cursor at the start has nothing before it, and one at the end has nothing after it")
    func cursorAtTheEnds() {
        let atStart = bound("hello world", cursor: 0)
        let atEnd = bound("hello world", cursor: 11)

        #expect(atStart.before.isEmpty)
        #expect(atStart.after == "hello world")
        #expect(atEnd.before == "hello world")
        #expect(atEnd.after.isEmpty)
    }

    @Test("a short field is kept whole around the cursor")
    func shortField() {
        let result = bound("hello world", cursor: 5)

        #expect(result == BoundedFieldText(before: "hello", after: " world", selection: ""))
    }

    @Test("the selection of a short field is kept")
    func shortSelection() {
        let result = bound("hello world", cursor: 6, length: 5)

        #expect(result == BoundedFieldText(before: "hello ", after: "", selection: "world"))
    }

    @Test("a cut never splits a character made of several scalars")
    func graphemeClustersAreKeptWhole() {
        // A family emoji is seven scalars and eleven UTF-16 units; an e with an accent is two scalars.
        let family = "👨‍👩‍👧"
        let accent = "e\u{301}"
        let text = String(repeating: family, count: 600) + String(repeating: accent, count: 600)
        let cursor = family.utf16.count * 600  // where the emoji end and the accents begin

        let result = bound(text, cursor: cursor)

        #expect(result.before.count == 500)
        #expect(result.after.count == 500)
        #expect(result.before.unicodeScalars.count > 500)  // counted in characters, not scalars
        #expect(result.before.allSatisfy { $0 == Character(family) })
        #expect(result.after.allSatisfy { $0 == Character(accent) })
    }

    @Test("a cursor inside a character counts as before it")
    func cursorInsideACharacter() {
        let text = "ab👨‍👩‍👧cd"
        let insideFamily = 2 + 3  // three units into the emoji

        let result = bound(text, cursor: insideFamily)

        #expect(result.before == "ab")
        #expect(result.after == "👨‍👩‍👧cd")
    }

    @Test("a selection that starts or ends inside a character takes the whole character")
    func selectionInsideCharacters() {
        let text = "a👍🏽b"  // the thumb and its skin tone are one character of four UTF-16 units
        let result = ContextBounds.bound(fieldText: text, selection: 2..<4, selectedText: nil)

        #expect(result.selection == "👍🏽")
        #expect(result.before == "a")
        #expect(result.after == "b")
    }

    @Test("a range that runs past the text is clamped")
    func clamped() {
        let result = ContextBounds.bound(fieldText: "hello", selection: 3..<99, selectedText: nil)

        #expect(result == BoundedFieldText(before: "hel", after: "", selection: "lo"))
    }

    @Test("without a range the cursor is unknown, so nothing is kept around it")
    func noRange() {
        let result = ContextBounds.bound(fieldText: "hello world", selection: nil, selectedText: "world")

        #expect(result == BoundedFieldText(before: "", after: "", selection: "world"))
    }

    @Test("without the field the selected text alone is kept, cut to 1000 characters")
    func selectedTextWithoutTheField() {
        let result = ContextBounds.bound(fieldText: nil, selection: nil, selectedText: Self.long)

        #expect(result.before.isEmpty)
        #expect(result.after.isEmpty)
        #expect(result.selection.count == 1_000)
    }

    @Test("an empty field gives nothing")
    func emptyField() {
        #expect(bound("", cursor: 0) == .empty)
        #expect(ContextBounds.bound(fieldText: nil, selection: nil, selectedText: nil) == .empty)
    }
}
