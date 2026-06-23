import Testing
import CoreGraphics
import CoreText
@testable import MarkdownTextEngine

// MARK: - Task 7.1: wordSelection pure helper tests

@Suite("wordSelection helper (Task 7.1)")
struct WordSelectionTests {

    // Lays out "hello world" in a wide canvas so it fits on one line.
    private func makeLayout() -> (layout: DocumentLayout, doc: TextDocument) {
        let s = TextStyle(fontSize: 17, color: .black)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("hello world", s)], style: .body))
        ])
        let layout = LayoutEngine.layout(doc, width: 400)
        return (layout, doc)
    }

    @Test("double-tap in the middle of 'hello' selects 'hello' (UTF-16 offsets 0..5)")
    func doubleTapMiddleOfHello() {
        let (layout, doc) = makeLayout()
        // Find the text line so we can compute a plausible x coordinate inside "hello".
        guard case .text(_, let lines) = layout.blocks[0], let line = lines.first else {
            Issue.record("expected a text block with at least one line")
            return
        }
        // Derive x-coordinate of char index 2 ("ll" region) via CTLine for font accuracy.
        let helloMidX = CTLineGetOffsetForStringIndex(line.ctLine, 2, nil)
        let pt = CGPoint(x: line.origin.x + helloMidX, y: line.origin.y + line.size.height / 2)
        let range = wordSelection(at: pt, layout: layout, doc: doc)
        // "hello" occupies UTF-16 offsets [0, 5).
        #expect(range.start.index == 0)
        #expect(range.end.index == 5)
    }

    @Test("double-tap in 'world' selects 'world' (UTF-16 offsets 6..11)")
    func doubleTapInWorld() {
        let (layout, doc) = makeLayout()
        guard case .text(_, let lines) = layout.blocks[0], let line = lines.first else {
            Issue.record("expected a text block with at least one line")
            return
        }
        // Derive the x coordinate for the start of "world" (offset 6) using CTLine.
        // This gives a font-metric–accurate coordinate regardless of the system font.
        let worldStartX = CTLineGetOffsetForStringIndex(line.ctLine, 6, nil)
        // Tap 3pt past the word boundary to land in the middle of "w".
        let pt = CGPoint(x: line.origin.x + worldStartX + 3, y: line.origin.y + line.size.height / 2)
        let range = wordSelection(at: pt, layout: layout, doc: doc)
        // "world" occupies UTF-16 offsets [6, 11).
        #expect(range.start.index == 6)
        #expect(range.end.index == 11)
    }

    @Test("wordSelection returns non-empty range on valid word")
    func wordSelectionNonEmpty() {
        let (layout, doc) = makeLayout()
        guard case .text(_, let lines) = layout.blocks[0], let line = lines.first else {
            Issue.record("expected a text block with at least one line")
            return
        }
        let pt = CGPoint(x: 10, y: line.origin.y + line.size.height / 2)
        let range = wordSelection(at: pt, layout: layout, doc: doc)
        #expect(range.start.index < range.end.index, "expected non-empty word range")
    }

    @Test("wordSelection above all text snaps to start and returns a range (may be zero-length)")
    func wordSelectionAboveText() {
        let (layout, doc) = makeLayout()
        let pt = CGPoint(x: 50, y: -100)
        let range = wordSelection(at: pt, layout: layout, doc: doc)
        // Should not crash; range must be structurally valid (start <= end).
        #expect(range.start.index <= range.end.index)
    }
}
