import Testing
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("Block stacking")
struct BlockStackingTests {

    @Test("two paragraphs: second block starts at or after first block maxY + spacingAfter")
    func twoBlocksStack() {
        let s = TextStyle(fontSize: 14, color: .black)
        // Use default ParagraphStyle which has spacingAfter = 8
        let p1 = Paragraph(runs: [.text("First paragraph text.", s)], style: .body)
        let p2 = Paragraph(runs: [.text("Second paragraph text.", s)], style: .body)
        let doc = TextDocument(blocks: [.paragraph(p1), .paragraph(p2)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard layout.blocks.count == 2 else {
            Issue.record("expected 2 blocks, got \(layout.blocks.count)"); return
        }
        guard case .text(let rect1, _) = layout.blocks[0],
              case .text(let rect2, _) = layout.blocks[1] else {
            Issue.record("blocks are not .text"); return
        }

        // Second block must start at or after the end of the first block + spacingAfter
        let expectedMinY = rect1.maxY + p1.style.spacingAfter
        #expect(rect2.origin.y >= expectedMinY)
    }

    @Test("contentSize.height equals last block maxY (no trailing spacingAfter gap)")
    func contentSizeEqualsLastBlockMaxY() {
        let s = TextStyle(fontSize: 14, color: .black)
        // ParagraphStyle.body has spacingAfter = 8. The contentSize.height must be
        // rect2.maxY exactly — it must NOT include the trailing 8pt spacingAfter.
        let p1 = Paragraph(runs: [.text("First paragraph.", s)], style: .body)
        let p2 = Paragraph(runs: [.text("Second paragraph.", s)], style: .body)
        let doc = TextDocument(blocks: [.paragraph(p1), .paragraph(p2)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .text(let rect2, _) = layout.blocks[1] else {
            Issue.record("second block is not .text"); return
        }
        // Exact equality: no trailing inter-block gap must be appended to contentSize.
        #expect(layout.contentSize.height == rect2.maxY)
    }

    @Test("three blocks: monotonically increasing minY")
    func threeBlocksMonotonic() {
        let s = TextStyle(fontSize: 14, color: .black)
        let blocks: [Block] = (1...3).map { i in
            .paragraph(Paragraph(runs: [.text("Paragraph \(i).", s)], style: .body))
        }
        let layout = LayoutEngine.layout(TextDocument(blocks: blocks), width: 400)
        guard layout.blocks.count == 3 else {
            Issue.record("expected 3 blocks"); return
        }
        let rects = layout.blocks.compactMap { block -> CGRect? in
            if case .text(let r, _) = block { return r }
            return nil
        }
        #expect(rects.count == 3)
        #expect(rects[1].minY > rects[0].minY)
        #expect(rects[2].minY > rects[1].minY)
    }
}
