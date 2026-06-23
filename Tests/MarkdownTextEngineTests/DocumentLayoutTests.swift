import Testing
import CoreText
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("DocumentLayout types")
struct DocumentLayoutTests {

    @Test("can construct a DocumentLayout with one text BlockFrame")
    func constructDocumentLayout() {
        // Build a minimal CTLine so we can form a LineFrame
        let attr = CFAttributedStringCreate(nil, "Hello" as CFString, nil)!
        let typesetter = CTTypesetterCreateWithAttributedString(attr)
        let ctLine = CTTypesetterCreateLine(typesetter, CFRangeMake(0, 5))

        let lineFrame = LineFrame(
            origin: CGPoint(x: 0, y: 0),
            size: CGSize(width: 40, height: 20),
            ascent: 14,
            descent: 4,
            ctLine: ctLine,
            charRange: 0..<5
        )

        let blockRect = CGRect(x: 0, y: 0, width: 200, height: 20)
        let blockFrame = BlockFrame.text(rect: blockRect, lines: [lineFrame])
        let layout = DocumentLayout(blocks: [blockFrame], contentSize: CGSize(width: 200, height: 20))

        #expect(layout.contentSize.width == 200)
        #expect(layout.contentSize.height == 20)
        guard case .text(let rect, let lines) = layout.blocks[0] else {
            Issue.record("expected .text block"); return
        }
        #expect(rect == blockRect)
        #expect(lines.count == 1)
        #expect(lines[0].origin == CGPoint(x: 0, y: 0))
        #expect(lines[0].ascent == 14)
        #expect(lines[0].descent == 4)
        #expect(lines[0].charRange == 0..<5)
    }
}
