import Testing
import CoreGraphics
import CoreText
@testable import MarkdownTextEngine

@Suite("Hit-testing")
struct HitTestingTests {

    private func makeLayout() -> (layout: DocumentLayout, doc: TextDocument) {
        let s = TextStyle(fontSize: 17, color: .black)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Hello world", s)], style: .body))
        ])
        let layout = LayoutEngine.layout(doc, width: 400)
        return (layout, doc)
    }

    @Test("hit at far left returns position 0")
    func hitAtFarLeft() throws {
        let (layout, doc) = makeLayout()
        guard case .text(let rect, _) = layout.blocks[0] else {
            Issue.record("not a text block"); return
        }
        let pt = CGPoint(x: 2, y: rect.midY)
        let pos = position(at: pt, in: layout, doc: doc)
        #expect(pos.index == 0)
    }

    @Test("hit at far right returns end of text")
    func hitAtFarRight() throws {
        let (layout, doc) = makeLayout()
        guard case .text(let rect, _) = layout.blocks[0] else {
            Issue.record("not a text block"); return
        }
        let pt = CGPoint(x: 9999, y: rect.midY)
        let pos = position(at: pt, in: layout, doc: doc)
        let expected = "Hello world".utf16.count
        #expect(pos.index == expected)
    }

    @Test("hit above all blocks snaps to start")
    func hitAboveAllBlocks() {
        let (layout, doc) = makeLayout()
        let pt = CGPoint(x: 50, y: -100)
        let pos = position(at: pt, in: layout, doc: doc)
        #expect(pos.index == 0)
    }

    @Test("hit below all blocks snaps to end")
    func hitBelowAllBlocks() {
        let (layout, doc) = makeLayout()
        let pt = CGPoint(x: 50, y: 99999)
        let pos = position(at: pt, in: layout, doc: doc)
        let expected = "Hello world".utf16.count
        #expect(pos.index == expected)
    }

    @Test("hit in second paragraph respects UTF-16 base offset")
    func hitInSecondParagraph() {
        let s = TextStyle(fontSize: 17, color: .black)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Hi", s)], style: .body)),
            .paragraph(Paragraph(runs: [.text("World", s)], style: .body))
        ])
        let layout = LayoutEngine.layout(doc, width: 400)
        // The second block's base UTF-16 offset = "Hi".utf16.count + 1 (separator) = 3
        guard case .text(let rect1, _) = layout.blocks[1] else {
            Issue.record("block[1] not text"); return
        }
        // Hit at far left of second paragraph → index == 3 (start of "World")
        let pt = CGPoint(x: 2, y: rect1.midY)
        let pos = position(at: pt, in: layout, doc: doc)
        let expectedBase = "Hi".utf16.count + 1  // "Hi\n" → 3
        #expect(pos.index == expectedBase)
    }
}
