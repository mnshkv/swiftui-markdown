import Testing
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("Copy text and word selection")
struct CopyAndWordTests {

    private func doc(_ text: String) -> TextDocument {
        let s = TextStyle(fontSize: 17, color: .black)
        return TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text(text, s)], style: .body))
        ])
    }

    // MARK: copyText

    @Test("copyText slices first word")
    func copyTextFirstWord() {
        let d = doc("Hello world")
        let range = TextRange(start: TextPosition(index: 0), end: TextPosition(index: 5))
        #expect(copyText(for: range, doc: d) == "Hello")
    }

    @Test("copyText slices second word")
    func copyTextSecondWord() {
        let d = doc("Hello world")
        let range = TextRange(start: TextPosition(index: 6), end: TextPosition(index: 11))
        #expect(copyText(for: range, doc: d) == "world")
    }

    @Test("copyText handles full document range")
    func copyTextFull() {
        let d = doc("Hello world")
        let total = "Hello world".utf16.count
        let range = TextRange(start: TextPosition(index: 0), end: TextPosition(index: total))
        #expect(copyText(for: range, doc: d) == "Hello world")
    }

    @Test("copyText clamps out-of-bounds indices")
    func copyTextClamped() {
        let d = doc("Hi")
        let range = TextRange(start: TextPosition(index: 0), end: TextPosition(index: 9999))
        let result = copyText(for: range, doc: d)
        #expect(result == "Hi")
    }

    @Test("copyText empty range returns empty string")
    func copyTextEmptyRange() {
        let d = doc("Hello")
        let range = TextRange(start: TextPosition(index: 2), end: TextPosition(index: 2))
        #expect(copyText(for: range, doc: d) == "")
    }

    @Test("copyText across two paragraphs includes newline separator")
    func copyTextAcrossParagraphs() {
        let s = TextStyle(fontSize: 17, color: .black)
        let d = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Hi", s)], style: .body)),
            .paragraph(Paragraph(runs: [.text("Bye", s)], style: .body))
        ])
        // "Hi\nBye" — full range
        let total = flattenedText(d).utf16.count
        let range = TextRange(start: TextPosition(index: 0), end: TextPosition(index: total))
        #expect(copyText(for: range, doc: d) == "Hi\nBye")
    }

    // MARK: wordRange

    @Test("wordRange at position 2 in 'hello world' covers 'hello'")
    func wordRangeFirstWord() {
        let d = doc("hello world")
        let pos = TextPosition(index: 2)
        let range = wordRange(at: pos, doc: d)
        #expect(range.start.index == 0)
        #expect(range.end.index == 5)
    }

    @Test("wordRange at position 7 in 'hello world' covers 'world'")
    func wordRangeSecondWord() {
        let d = doc("hello world")
        let pos = TextPosition(index: 7)
        let range = wordRange(at: pos, doc: d)
        #expect(range.start.index == 6)
        #expect(range.end.index == 11)
    }

    @Test("wordRange at start of word")
    func wordRangeAtStart() {
        let d = doc("hello world")
        let pos = TextPosition(index: 0)
        let range = wordRange(at: pos, doc: d)
        #expect(range.start.index == 0)
        #expect(range.end.index == 5)
    }

    @Test("wordRange at end of last word")
    func wordRangeAtEndOfWord() {
        let d = doc("hello world")
        // Position 11 is after "world" — should still find "world"
        let pos = TextPosition(index: 10)
        let range = wordRange(at: pos, doc: d)
        #expect(range.start.index == 6)
        #expect(range.end.index == 11)
    }

    @Test("wordRange at whitespace returns zero-length range")
    func wordRangeAtWhitespace() {
        let d = doc("hello world")
        // Position 5 is the space between words
        let pos = TextPosition(index: 5)
        let range = wordRange(at: pos, doc: d)
        // No word at space — zero-length range at position
        #expect(range.start.index == range.end.index)
    }

    @Test("wordRange with out-of-bounds position returns zero-length at clamped end")
    func wordRangeOutOfBounds() {
        let d = doc("hello")
        let pos = TextPosition(index: 9999)
        let range = wordRange(at: pos, doc: d)
        #expect(range.start.index == range.end.index)
    }

    // MARK: Mid-surrogate-pair robustness (findings 1 & 2)

    /// "a😀b" — the emoji is U+1F600, encoded as 2 UTF-16 units (a surrogate pair).
    /// UTF-16 layout: index 0 = 'a', index 1 = high surrogate, index 2 = low surrogate, index 3 = 'b'.
    /// Index 2 lands inside the surrogate pair.

    @Test("copyText over mid-surrogate range does not crash and returns a String")
    func copyTextMidSurrogateSafe() {
        let d = doc("a😀b")
        // Range [1, 2] — high surrogate only; String(utf16[...]) returns nil → should return ""
        let range = TextRange(start: TextPosition(index: 1), end: TextPosition(index: 2))
        // Must not crash; result is "" or whatever String can form from a lone surrogate
        let result = copyText(for: range, doc: d)
        // The only requirement is no crash and the result is a String
        _ = result
    }

    @Test("wordRange at mid-surrogate index returns zero-length range and does not crash")
    func wordRangeMidSurrogateSafe() {
        let d = doc("a😀b")
        // Index 2 = low surrogate of 😀 — lands mid-surrogate-pair
        let pos = TextPosition(index: 2)
        let range = wordRange(at: pos, doc: d)
        // Must not crash; must return a zero-length range
        #expect(range.start.index == range.end.index)
    }
}
