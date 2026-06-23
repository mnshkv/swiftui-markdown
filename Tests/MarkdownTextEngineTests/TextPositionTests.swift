import Testing
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("TextPosition and flattenedText")
struct TextPositionTests {

    // MARK: flattenedText

    @Test("two paragraphs joined with newline")
    func twoParagraphsJoined() {
        let s = TextStyle(fontSize: 17, color: .black)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Hello", s)], style: .body)),
            .paragraph(Paragraph(runs: [.text("World", s)], style: .body))
        ])
        #expect(flattenedText(doc) == "Hello\nWorld")
    }

    @Test("single paragraph no separator")
    func singleParagraph() {
        let s = TextStyle(fontSize: 17, color: .black)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Hi", s)], style: .body))
        ])
        #expect(flattenedText(doc) == "Hi")
    }

    @Test("hard lineBreak becomes newline in flattened text")
    func hardLineBreakBecomesNewline() {
        let s = TextStyle(fontSize: 17, color: .black)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [
                .text("A", s),
                .lineBreak(hard: true),
                .text("B", s)
            ], style: .body))
        ])
        #expect(flattenedText(doc) == "A\nB")
    }

    @Test("soft lineBreak becomes LINE SEPARATOR in flattened text")
    func softLineBreakBecomesLineSeparator() {
        let s = TextStyle(fontSize: 17, color: .black)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [
                .text("A", s),
                .lineBreak(hard: false),
                .text("B", s)
            ], style: .body))
        ])
        #expect(flattenedText(doc) == "A\u{2028}B")
    }

    @Test("link inner runs are included in flattened text")
    func linkInnerRuns() {
        let s = TextStyle(fontSize: 17, color: .black)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [
                .link(runs: [.text("click", s)], payload: LinkPayload("url"))
            ], style: .body))
        ])
        #expect(flattenedText(doc) == "click")
    }

    @Test("inlineImage contributes U+FFFC placeholder (1 UTF-16 unit)")
    func inlineImagePlaceholder() {
        let s = TextStyle(fontSize: 17, color: .black)
        let img = ImageAttachment(source: "x.png", intrinsicSize: CGSize(width: 10, height: 10), alt: "img")
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [
                .text("A", s),
                .inlineImage(img),
                .text("B", s)
            ], style: .body))
        ])
        // INDEX SPACE CONTRACT: .inlineImage → U+FFFC (1 UTF-16 unit), matching
        // the single placeholder character inserted by buildAttributedString.
        #expect(flattenedText(doc) == "A\u{FFFC}B")
        #expect(flattenedText(doc).utf16.count == 3)  // "A" + U+FFFC + "B"
    }

    @Test("non-paragraph blocks contribute nothing but still get separator")
    func nonParagraphBlockSeparator() {
        let s = TextStyle(fontSize: 17, color: .black)
        let rule = RuleStyle(color: .black)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("A", s)], style: .body)),
            .thematicBreak(rule),
            .paragraph(Paragraph(runs: [.text("B", s)], style: .body))
        ])
        // Separators between every adjacent pair: "A" + "\n" + "" + "\n" + "B"
        #expect(flattenedText(doc) == "A\n\nB")
    }

    @Test("empty document gives empty string")
    func emptyDocument() {
        let doc = TextDocument(blocks: [])
        #expect(flattenedText(doc) == "")
    }

    // MARK: TextRange normalization

    @Test("TextRange normalizes so start <= end")
    func textRangeNormalizes() {
        let range = TextRange(start: TextPosition(index: 5), end: TextPosition(index: 2))
        #expect(range.start.index == 2)
        #expect(range.end.index == 5)
    }

    @Test("TextRange keeps order when start <= end")
    func textRangeKeepsOrder() {
        let range = TextRange(start: TextPosition(index: 0), end: TextPosition(index: 10))
        #expect(range.start.index == 0)
        #expect(range.end.index == 10)
    }

    // MARK: TextPosition Comparable

    @Test("TextPosition comparison")
    func textPositionComparable() {
        #expect(TextPosition(index: 0) < TextPosition(index: 1))
        #expect(!(TextPosition(index: 1) < TextPosition(index: 0)))
        #expect(!(TextPosition(index: 3) < TextPosition(index: 3)))
    }
}
