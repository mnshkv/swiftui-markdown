import Testing
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("ParagraphLayout")
struct ParagraphLayoutTests {

    @Test("a paragraph wider than the box wraps into two lines")
    func wraps() {
        let s = TextStyle(fontSize: 17, color: .black)
        let p = Paragraph(runs: [.text("aaaa bbbb cccc dddd eeee", s)], style: .body)
        let layout = LayoutEngine.layout(TextDocument(blocks: [.paragraph(p)]), width: 80)
        guard case .text(_, let lines) = layout.blocks[0] else {
            Issue.record("not text"); return
        }
        #expect(lines.count >= 2)
        #expect(lines[1].origin.y > lines[0].origin.y)     // second line is below the first
        #expect(lines.allSatisfy { $0.origin.x == 0 })     // leading-aligned, no indent
    }

    @Test("layout returns correct contentSize covering the block")
    func contentSizeCoversBlock() {
        let s = TextStyle(fontSize: 14, color: .black)
        let p = Paragraph(runs: [.text("Hello world", s)], style: .body)
        let layout = LayoutEngine.layout(TextDocument(blocks: [.paragraph(p)]), width: 400)
        #expect(layout.contentSize.height > 0)
        #expect(layout.contentSize.width == 400)
        guard case .text(let rect, _) = layout.blocks[0] else {
            Issue.record("not text"); return
        }
        #expect(rect.maxY <= layout.contentSize.height)
    }

    @Test("spacingBefore and spacingAfter shift block origin")
    func spacingBefore() {
        let s = TextStyle(fontSize: 14, color: .black)
        let pStyle = ParagraphStyle(spacingBefore: 20, spacingAfter: 10)
        let p = Paragraph(runs: [.text("Hi", s)], style: pStyle)
        let layout = LayoutEngine.layout(TextDocument(blocks: [.paragraph(p)]), width: 300)
        guard case .text(let rect, _) = layout.blocks[0] else {
            Issue.record("not text"); return
        }
        // Block rect origin.y should reflect spacingBefore
        #expect(rect.origin.y >= 20)
    }
}
