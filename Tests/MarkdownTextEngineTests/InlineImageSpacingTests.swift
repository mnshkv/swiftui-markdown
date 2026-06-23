import Testing
import CoreText
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("Inline image spacing")
struct InlineImageSpacingTests {
    // Regression: the inline-image run delegate must size ONLY the placeholder
    // glyph. Text inserted after the placeholder inherits its attributes, so if
    // the delegate is not cleared the following glyphs all take the image width
    // (visible as exploded letter-spacing). Exactly one glyph may carry it.
    @Test("run delegate does not bleed into text after an inline image")
    func delegateDoesNotBleed() {
        let s = TextStyle(fontSize: 16, color: .black)
        let imageWidth: CGFloat = 20
        let paragraph = Paragraph(runs: [
            .text("AB ", s),
            .inlineImage(ImageAttachment(source: "x",
                                         intrinsicSize: CGSize(width: imageWidth, height: imageWidth),
                                         alt: "i")),
            .text(" CD EF GH", s),
        ], style: .body)
        let layout = LayoutEngine.layout(TextDocument(blocks: [.paragraph(paragraph)]), width: 400)
        guard case .text(_, let lines) = layout.blocks.first, let line = lines.first else {
            Issue.record("expected a text line")
            return
        }

        guard let runs = CTLineGetGlyphRuns(line.ctLine) as? [CTRun] else {
            Issue.record("expected glyph runs")
            return
        }
        var glyphsAtImageWidth = 0
        var totalGlyphs = 0
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            var advances = Array(repeating: CGSize.zero, count: count)
            CTRunGetAdvances(run, CFRangeMake(0, 0), &advances)
            for advance in advances {
                totalGlyphs += 1
                if abs(advance.width - imageWidth) < 0.5 { glyphsAtImageWidth += 1 }
            }
        }

        #expect(totalGlyphs == 13) // "AB " (3) + image (1) + " CD EF GH" (9)
        #expect(glyphsAtImageWidth == 1,
                "only the placeholder should carry the image width; got \(glyphsAtImageWidth)")
    }
}
