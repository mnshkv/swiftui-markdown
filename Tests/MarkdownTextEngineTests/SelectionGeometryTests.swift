import Testing
import CoreGraphics
import CoreText
@testable import MarkdownTextEngine

@Suite("SelectionGeometry")
struct SelectionGeometryTests {

    private func makeDoc(_ text: String) -> TextDocument {
        let s = TextStyle(fontSize: 17, color: .black)
        return TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text(text, s)], style: .body))
        ])
    }

    @Test("full-line selection returns one rect with positive width")
    func fullLineSelection() {
        let doc = makeDoc("Hello world")
        let layout = LayoutEngine.layout(doc, width: 400)
        guard case .text(_, let lines) = layout.blocks[0], !lines.isEmpty else {
            Issue.record("no lines"); return
        }
        // Single line — select the entire content
        let totalLen = "Hello world".utf16.count
        let range = TextRange(start: TextPosition(index: 0), end: TextPosition(index: totalLen))
        let rects = selectionRects(for: range, in: layout, doc: doc)
        #expect(rects.count == 1)
        #expect(rects[0].width > 0)
    }

    @Test("two-line selection returns two rects")
    func twoLineSelection() {
        // Use a narrow width to force wrapping
        let s = TextStyle(fontSize: 17, color: .black)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("aaaa bbbb cccc dddd eeee ffff", s)], style: .body))
        ])
        let layout = LayoutEngine.layout(doc, width: 80)
        guard case .text(_, let lines) = layout.blocks[0], lines.count >= 2 else {
            Issue.record("need at least 2 lines"); return
        }
        // Select from start of line 0 to end of line 1
        let endIndex = lines[1].charRange.upperBound
        let range = TextRange(start: TextPosition(index: 0), end: TextPosition(index: endIndex))
        let rects = selectionRects(for: range, in: layout, doc: doc)
        #expect(rects.count >= 2)
    }

    @Test("empty range returns no rects")
    func emptyRangeReturnsNoRects() {
        let doc = makeDoc("Hello")
        let layout = LayoutEngine.layout(doc, width: 400)
        let range = TextRange(start: TextPosition(index: 2), end: TextPosition(index: 2))
        let rects = selectionRects(for: range, in: layout, doc: doc)
        #expect(rects.isEmpty)
    }

    @Test("selection rect y matches line origin y")
    func selectionRectYMatchesLineOrigin() {
        let doc = makeDoc("Hello world")
        let layout = LayoutEngine.layout(doc, width: 400)
        guard case .text(_, let lines) = layout.blocks[0], !lines.isEmpty else {
            Issue.record("no lines"); return
        }
        let totalLen = "Hello world".utf16.count
        let range = TextRange(start: TextPosition(index: 0), end: TextPosition(index: totalLen))
        let rects = selectionRects(for: range, in: layout, doc: doc)
        #expect(!rects.isEmpty)
        #expect(rects[0].origin.y == lines[0].origin.y)
        #expect(rects[0].height == lines[0].size.height)
    }

    @Test("selection in second paragraph uses correct base offset")
    func selectionInSecondParagraph() {
        let s = TextStyle(fontSize: 17, color: .black)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Hi", s)], style: .body)),
            .paragraph(Paragraph(runs: [.text("World", s)], style: .body))
        ])
        let layout = LayoutEngine.layout(doc, width: 400)
        // "Hi\nWorld" — "World" starts at UTF-16 index 3
        let base = "Hi".utf16.count + 1
        let range = TextRange(start: TextPosition(index: base), end: TextPosition(index: base + "World".utf16.count))
        let rects = selectionRects(for: range, in: layout, doc: doc)
        #expect(rects.count == 1)
        #expect(rects[0].width > 0)
    }
}
