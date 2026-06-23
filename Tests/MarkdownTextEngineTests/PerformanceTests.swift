import Testing
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("Performance: windowed draw culling")
struct PerformanceTests {

    @Test("large document: visibleBlockIndices returns only blocks in visible window")
    func largeDocumentWindowedCulling() {
        // Build a document with 2000 paragraphs.
        let style = TextStyle(fontSize: 14, color: CGColor(gray: 0, alpha: 1))
        let blocks = (0..<2000).map { i in
            Block.paragraph(Paragraph(
                runs: [.text("Paragraph \(i)", style)],
                style: .body
            ))
        }
        let doc = TextDocument(blocks: blocks)
        let layout = LayoutEngine.layout(doc, width: 400)

        // The layout must have 2000 blocks.
        #expect(layout.blocks.count == 2000)

        // Each paragraph at font size 14 is roughly 20-40 pts tall.
        // The top-most 3 blocks should be in a visible rect of height 200.
        let topVisible = CGRect(x: 0, y: 0, width: 400, height: 200)
        let topIndices = layout.visibleBlockIndices(in: topVisible)

        // Should be a small number (say < 50) but definitely not all 2000.
        #expect(topIndices.count < 50, "Expected few blocks in top visible window, got \(topIndices.count)")
        #expect(!topIndices.isEmpty, "Expected at least one visible block in top window")

        // The bottom 200 pt window should return different (non-zero) indices.
        let totalH = layout.contentSize.height
        let bottomVisible = CGRect(x: 0, y: totalH - 200, width: 400, height: 200)
        let bottomIndices = layout.visibleBlockIndices(in: bottomVisible)
        #expect(!bottomIndices.isEmpty, "Expected blocks in bottom visible window")

        // Top and bottom indices must not overlap (they are far apart in a 2000-para doc).
        let topSet = Set(topIndices)
        let bottomSet = Set(bottomIndices)
        #expect(topSet.isDisjoint(with: bottomSet), "Top and bottom visible windows must not share blocks")
    }
}
