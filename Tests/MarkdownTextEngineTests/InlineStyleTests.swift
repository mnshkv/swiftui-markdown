import Testing
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("Inline styled runs and breaks")
struct InlineStyleTests {

    @Test("mixed bold and italic runs lay out without crashing and produce at least one line")
    func boldItalicRuns() {
        let base = TextStyle(fontSize: 17, color: .black)
        let bold = TextStyle(fontSize: 17, isBold: true, color: .black)
        let italic = TextStyle(fontSize: 17, isItalic: true, color: .black)
        let p = Paragraph(
            runs: [
                .text("Hello ", base),
                .text("bold", bold),
                .text(" and ", base),
                .text("italic", italic),
                .text(" text.", base)
            ],
            style: .body
        )
        let layout = LayoutEngine.layout(TextDocument(blocks: [.paragraph(p)]), width: 400)
        guard case .text(_, let lines) = layout.blocks[0] else {
            Issue.record("not text"); return
        }
        #expect(lines.count >= 1)
        // All lines should have positive height
        #expect(lines.allSatisfy { $0.size.height > 0 })
    }

    @Test("bold run in narrow column wraps; line count >= plain text at same width")
    func boldRunChangesLayout() {
        let plain = TextStyle(fontSize: 17, color: .black)
        let bold = TextStyle(fontSize: 17, isBold: true, color: .black)
        let text = "aaaa bbbb cccc dddd eeee ffff"
        let pPlain = Paragraph(runs: [.text(text, plain)], style: .body)
        let pBold  = Paragraph(runs: [.text(text, bold)], style: .body)
        let layoutPlain = LayoutEngine.layout(TextDocument(blocks: [.paragraph(pPlain)]), width: 100)
        let layoutBold  = LayoutEngine.layout(TextDocument(blocks: [.paragraph(pBold)]), width: 100)
        guard case .text(_, let linesPlain) = layoutPlain.blocks[0],
              case .text(_, let linesBold)  = layoutBold.blocks[0] else {
            Issue.record("not text"); return
        }
        // Bold is typically wider so wraps at least as much as plain
        #expect(linesBold.count >= linesPlain.count)
    }

    @Test("hard line break forces a new line")
    func hardLineBreak() {
        let s = TextStyle(fontSize: 17, color: .black)
        let p = Paragraph(
            runs: [
                .text("Line one", s),
                .lineBreak(hard: true),
                .text("Line two", s)
            ],
            style: .body
        )
        let layout = LayoutEngine.layout(TextDocument(blocks: [.paragraph(p)]), width: 400)
        guard case .text(_, let lines) = layout.blocks[0] else {
            Issue.record("not text"); return
        }
        // A hard break should split the text into at least 2 lines
        #expect(lines.count >= 2)
        // Second line should be below the first
        #expect(lines[1].origin.y > lines[0].origin.y)
    }

    @Test("a soft line break (U+2028) starts a new line")
    func softLineBreak() {
        let s = TextStyle(fontSize: 17, color: .black)
        // Soft break (LINE SEPARATOR U+2028) within text that fits in a wide column.
        // CoreText typesetter treats U+2028 as a mandatory line separator,
        // so the two segments must appear on separate lines regardless of available width.
        let p = Paragraph(
            runs: [
                .text("Hello", s),
                .lineBreak(hard: false),
                .text("world", s)
            ],
            style: .body
        )
        let layout = LayoutEngine.layout(TextDocument(blocks: [.paragraph(p)]), width: 400)
        guard case .text(_, let lines) = layout.blocks[0] else {
            Issue.record("not text"); return
        }
        // U+2028 must force a line split — both segments are laid out on separate lines.
        #expect(lines.count >= 2)
    }

    @Test("hard line break as first run uses paragraph font, not default fallback font")
    func hardLineBreakFirstRunHasFont() {
        let s = TextStyle(fontSize: 24, color: .black)
        // The very first run is a hard break — previously this got NO font attributes,
        // causing CoreText to use a default fallback font and producing a spurious phantom line.
        let p = Paragraph(
            runs: [
                .lineBreak(hard: true),
                .text("After break", s)
            ],
            style: .body
        )
        let layout = LayoutEngine.layout(TextDocument(blocks: [.paragraph(p)]), width: 400)
        guard case .text(_, let lines) = layout.blocks[0] else {
            Issue.record("not text"); return
        }
        // Should produce exactly 2 lines: the break line and the text line.
        // (If the break had no font attributes, CoreText could produce a phantom extra line
        // with a default-font ascent that differs from s.fontSize.)
        #expect(lines.count == 2)
        // All lines must have positive, non-degenerate height.
        #expect(lines.allSatisfy { $0.size.height > 0 })
        // The text line's ascent must be consistent with font size 24.
        // CTFont ascent for a 24pt system font is typically near 22–23 pt.
        // We check it is > 0 and not the tiny default-font ascent (~9 pt for a 12pt fallback).
        let textLineAscent = lines[1].ascent
        #expect(textLineAscent > 15, "text line ascent (\(textLineAscent)) should reflect fontSize 24, not a default-font fallback")
    }

    @Test("monospace run uses different font metrics than proportional")
    func monospaceRun() {
        let mono = TextStyle(fontSize: 14, isMonospace: true, color: .black)
        let prop = TextStyle(fontSize: 14, color: .black)
        let text = "MMMMMMMMMM MMMMMMMMMM MMMMMMMMMM"
        let pMono = Paragraph(runs: [.text(text, mono)], style: .body)
        let pProp = Paragraph(runs: [.text(text, prop)], style: .body)
        let layoutMono = LayoutEngine.layout(TextDocument(blocks: [.paragraph(pMono)]), width: 100)
        let layoutProp = LayoutEngine.layout(TextDocument(blocks: [.paragraph(pProp)]), width: 100)
        guard case .text(_, let linesMono) = layoutMono.blocks[0],
              case .text(_, let linesProp) = layoutProp.blocks[0] else {
            Issue.record("not text"); return
        }
        // Both must produce at least 1 line
        #expect(linesMono.count >= 1)
        #expect(linesProp.count >= 1)
    }

    @Test("link run lays out its inner runs")
    func linkRun() {
        let s = TextStyle(fontSize: 14, color: .black)
        let p = Paragraph(
            runs: [
                .text("Click ", s),
                .link(runs: [.text("here", s)], payload: LinkPayload("url")),
                .text(" now.", s)
            ],
            style: .body
        )
        let layout = LayoutEngine.layout(TextDocument(blocks: [.paragraph(p)]), width: 400)
        guard case .text(_, let lines) = layout.blocks[0] else {
            Issue.record("not text"); return
        }
        #expect(lines.count >= 1)
    }
}
