import Testing
import TextShaping

@Suite("Correction diff")
struct CorrectionDiffTests {
    private static let inserted = "I spoke with Kyle Thorn about the launch."

    private static func diff(
        _ field: String, before: String = "Hello team. ", after: String = " See you.", hint: Int? = nil,
        inserted: String = inserted
    ) -> [WordCorrection]? {
        CorrectionDiff.corrections(inserted: inserted, anchorBefore: before, anchorAfter: after, in: field, near: hint)
    }

    // MARK: Anchors

    @Test("the region between the anchors is compared, in the middle of the field")
    func middle() {
        let field = "Hello team. I spoke with Kaelthorn about the launch. See you."

        #expect(Self.diff(field) == [WordCorrection(heard: "Kyle Thorn", corrected: "Kaelthorn")])
    }

    @Test("an empty text before pins the region to the start of the field")
    func atStart() {
        let field = "I spoke with Kaelthorn about the launch. See you."

        #expect(Self.diff(field, before: "") == [WordCorrection(heard: "Kyle Thorn", corrected: "Kaelthorn")])
    }

    @Test("an empty text after ends the region a little after the dictation, so later typing is only an insertion")
    func atEnd() {
        let field = "Hello team. I spoke with Kaelthorn about the launch. And then I added more words"

        #expect(Self.diff(field, after: "") == [WordCorrection(heard: "Kyle Thorn", corrected: "Kaelthorn")])
    }

    @Test("a repeated text before is taken nearest the cursor")
    func repeatedAnchor() {
        let first = "Hello team. I spoke with Kyle Thorn about the launch. See you."
        let second = " Hello team. I spoke with Kaelthorn about the launch. See you."
        let field = first + second

        #expect(
            Self.diff(field, hint: field.utf16.count) == [WordCorrection(heard: "Kyle Thorn", corrected: "Kaelthorn")])
        #expect(Self.diff(field, hint: 0) == [])
    }

    @Test("with no text around it, the dictation is found when most of its words are still there")
    func noAnchors() {
        let corrected = [WordCorrection(heard: "Kyle Thorn", corrected: "Kaelthorn")]
        #expect(Self.diff("I spoke with Kaelthorn about the launch.", before: "", after: "") == corrected)
        #expect(
            Self.diff("I spoke with Kaelthorn about the launch. And more words.", before: "", after: "") == corrected)
        #expect(Self.diff("Kaelthorn", before: "", after: "", inserted: "Kyle Thorn") == corrected)
    }

    @Test("with no text around it, a field that shares only a few of the dictation's words is another field")
    func noAnchorsOtherField() {
        #expect(Self.diff("We spoke with Kaelthorn about it.", before: "", after: "") == nil)
        #expect(Self.diff("Search", before: "", after: "") == nil)
    }

    @Test("a missing anchor gives up")
    func missingAnchor() {
        #expect(Self.diff("Something else entirely.") == nil)
        #expect(Self.diff("Hello team. I spoke with Kaelthorn about the launch.") == nil)
    }

    @Test("a field over the size limit gives up")
    func oversize() {
        let field =
            "Hello team. I spoke with Kaelthorn about the launch. See you."
            + String(repeating: "x", count: CorrectionDiff.maxFieldLength)

        #expect(Self.diff(field) == nil)
    }

    // MARK: Hunks

    @Test("a field with no change gives no correction")
    func unchanged() {
        #expect(Self.diff("Hello team. I spoke with Kyle Thorn about the launch. See you.") == [])
    }

    @Test("pure insertions and deletions are not corrections")
    func insertionsAndDeletions() {
        #expect(Self.diff("Hello team. I spoke with Kyle Thorn today about the launch. See you.") == [])
        #expect(Self.diff("Hello team. I spoke with Kyle Thorn about launch. See you.") == [])
    }

    @Test("a single replaced word is a correction, with the user's spelling")
    func singleWord() {
        let inserted = "Ask Jon about the deck."
        let field = "Hello team. Ask Jhon about the deck. See you."

        #expect(Self.diff(field, inserted: inserted) == [WordCorrection(heard: "Jon", corrected: "Jhon")])
    }

    @Test("several separate corrections are each found")
    func multiple() {
        let inserted = "Kyle Thorn met Jon today."
        let field = "Hello team. Kaelthorn met Jhon today. See you."

        #expect(
            Self.diff(field, inserted: inserted) == [
                WordCorrection(heard: "Kyle Thorn", corrected: "Kaelthorn"),
                WordCorrection(heard: "Jon", corrected: "Jhon"),
            ])
    }

    @Test("a replacement of more than three words is a rewrite, not a correction")
    func longRewrite() {
        let inserted = "we should meet next week to talk"
        let field = "Hello team. we could perhaps maybe gather next week to talk See you."

        #expect(Self.diff(field, inserted: inserted) == [])
    }

    @Test("a change of accents only is kept")
    func accentOnly() {
        let inserted = "Call Jose tomorrow."
        let field = "Hello team. Call José tomorrow. See you."

        #expect(Self.diff(field, inserted: inserted) == [WordCorrection(heard: "Jose", corrected: "José")])
    }

    @Test("a change of case or punctuation only is dropped")
    func caseAndPunctuation() {
        let inserted = "call kaelthorn tomorrow"
        #expect(Self.diff("Hello team. Call Kaelthorn tomorrow. See you.", inserted: inserted) == [])
        #expect(Self.diff("Hello team. call, kaelthorn tomorrow! See you.", inserted: inserted) == [])
    }
}
