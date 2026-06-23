import Testing
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("Glyph orientation")
struct GlyphOrientationTests {
    // Uppercase letters put all their ink ABOVE the baseline (cap height, no
    // descenders). Rendered upright, the ink sits above the baseline row;
    // rendered upside-down (the bug this guards against — a y-flipped context
    // without a compensating text matrix), the ink would mirror to below it.
    @Test("text renders upright, not vertically mirrored")
    func textRendersUpright() {
        let style = TextStyle(fontSize: 28, color: .black)
        let paragraph = Paragraph(runs: [.text("HELLO", style)], style: .body)
        let layout = LayoutEngine.layout(TextDocument(blocks: [.paragraph(paragraph)]), width: 300)
        guard case .text(_, let lines) = layout.blocks.first, let line = lines.first else {
            Issue.record("expected a text block with a line")
            return
        }

        let width = 300, height = 90
        // The bitmap memory row of a document-space y is ~y (the renderer maps
        // document-top to image-top); the baseline is at origin.y + ascent.
        let baselineRow = Int((line.origin.y + line.ascent).rounded())

        guard let (ctx, buffer) = makeWhiteContext(width: width, height: height) else {
            Issue.record("could not create bitmap context")
            return
        }
        defer { buffer.deallocate() }

        DocumentRenderer.draw(
            layout, in: ctx, canvasHeight: CGFloat(height),
            visible: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
            selection: []
        )

        var above = 0, below = 0
        for y in 0..<height {
            for x in 0..<width where pixel(at: x, y: y, width: width, buffer: buffer).r < 128 {
                if y < baselineRow { above += 1 } else if y > baselineRow { below += 1 }
            }
        }

        #expect(above > 0, "no glyph ink found")
        #expect(above > below * 3,
                "uppercase ink should sit above the baseline (upright); above=\(above) below=\(below)")
    }
}
