import Testing
import CoreText
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("Inline image CTRunDelegate (Task 6.2)")
struct InlineImageTests {

    private let textStyle = TextStyle(fontSize: 17, color: .black)

    // MARK: - Helpers

    /// Builds a paragraph with a single `.text` run and lays it out at width 400.
    private func textOnlyLineHeight(text: String) -> (ascent: CGFloat, height: CGFloat) {
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text(text, textStyle)], style: .body))
        ])
        let layout = LayoutEngine.layout(doc, width: 400)
        guard case .text(_, let lines) = layout.blocks[0], let line = lines.first else {
            return (0, 0)
        }
        return (line.ascent, line.size.height)
    }

    // MARK: 6.2.1 — Line with large inline image is taller than text-only line

    @Test("line containing inline image is taller than same line without it")
    func inlineImageMakesLineTaller() throws {
        let baseHeight = textOnlyLineHeight(text: "Hello").height

        // Insert a large inline image (100x100) next to text
        let img = ImageAttachment(source: "test.png",
                                  intrinsicSize: CGSize(width: 100, height: 100),
                                  alt: "icon")
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(
                runs: [.text("Hello ", textStyle), .inlineImage(img), .text(" World", textStyle)],
                style: .body
            ))
        ])
        let layout = LayoutEngine.layout(doc, width: 400)
        guard case .text(_, let lines) = layout.blocks[0], let line = lines.first else {
            Issue.record("expected text block with lines"); return
        }
        #expect(line.size.height > baseHeight,
                "line with a 100pt-tall image must be taller than a text-only line (\(baseHeight)pt)")
    }

    // MARK: 6.2.2 — Line ascent grows to accommodate image ascent

    @Test("line ascent grows when inline image ascent exceeds text ascent")
    func inlineImageGrowsAscent() throws {
        let baseAscent = textOnlyLineHeight(text: "X").ascent

        let img = ImageAttachment(source: "big.png",
                                  intrinsicSize: CGSize(width: 50, height: 200),
                                  alt: "tall")
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(
                runs: [.text("X", textStyle), .inlineImage(img)],
                style: .body
            ))
        ])
        let layout = LayoutEngine.layout(doc, width: 400)
        guard case .text(_, let lines) = layout.blocks[0], let line = lines.first else {
            Issue.record("expected text block with lines"); return
        }
        #expect(line.ascent > baseAscent,
                "ascent must grow when image ascent (\(200 * 0.80)pt) > text ascent (\(baseAscent)pt)")
    }

    // MARK: 6.2.3 — Small inline image does not shrink line below normal text height

    @Test("tiny inline image does not reduce line height below text-only baseline")
    func tinyInlineImageNoShrink() throws {
        let baseHeight = textOnlyLineHeight(text: "Hello").height

        let img = ImageAttachment(source: "icon.png",
                                  intrinsicSize: CGSize(width: 4, height: 4),
                                  alt: "dot")
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(
                runs: [.text("Hello", textStyle), .inlineImage(img)],
                style: .body
            ))
        ])
        let layout = LayoutEngine.layout(doc, width: 400)
        guard case .text(_, let lines) = layout.blocks[0], let line = lines.first else {
            Issue.record("expected text block with lines"); return
        }
        // CoreText takes the max of text and delegate metrics, so height must be >= text height.
        #expect(line.size.height >= baseHeight,
                "line height must not shrink below text-only height (\(baseHeight)pt)")
    }

    // MARK: 6.2.4 — buildAttributedString inserts exactly 1 UTF-16 unit for .inlineImage

    @Test("buildAttributedString inserts exactly 1 UTF-16 unit for .inlineImage")
    func inlineImageUtf16Length() {
        let img = ImageAttachment(source: "x.png", intrinsicSize: CGSize(width: 20, height: 20), alt: "img")
        let attrStr = buildAttributedString(from: [
            .text("A", textStyle),
            .inlineImage(img),
            .text("B", textStyle)
        ])
        // Expected: "A" (1) + U+FFFC (1) + "B" (1) = 3 UTF-16 units
        #expect(CFAttributedStringGetLength(attrStr) == 3,
                "must be exactly 3 UTF-16 units: A + U+FFFC + B")
    }

    // MARK: 6.2.5 — Zero intrinsicSize inline image does not crash

    @Test("zero intrinsicSize inline image does not crash layout")
    func zeroIntrinsicSizeInlineImage() {
        let img = ImageAttachment(source: "unknown.png", intrinsicSize: .zero, alt: "?")
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(
                runs: [.text("A", textStyle), .inlineImage(img), .text("B", textStyle)],
                style: .body
            ))
        ])
        let layout = LayoutEngine.layout(doc, width: 400)
        // Must not crash; must produce at least one line
        guard case .text(_, let lines) = layout.blocks[0] else {
            Issue.record("expected text block"); return
        }
        #expect(!lines.isEmpty, "layout must produce at least one line even with zero-size image")
    }
}
