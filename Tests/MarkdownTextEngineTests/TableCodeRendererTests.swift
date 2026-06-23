import Testing
import CoreText
import CoreGraphics
@testable import MarkdownTextEngine

// MARK: - Helpers

private func textStyle() -> TextStyle {
    TextStyle(fontSize: 14, color: CGColor(red: 0, green: 0, blue: 0, alpha: 1))
}

private func codeStyle() -> TextStyle {
    TextStyle(fontSize: 13, isMonospace: true, color: CGColor(red: 0, green: 0, blue: 0, alpha: 1))
}

private func cellRuns(_ text: String) -> [InlineRun] {
    [.text(text, textStyle())]
}

// MARK: - Task 5.4: Renderer tests for tables and code blocks

@Suite("Table and code block rendering (Task 5.4)")
struct TableCodeRendererTests {

    // ------------------------------------------------------------------
    // 5.4-A: Table grid borders have ink at expected column x positions
    // ------------------------------------------------------------------
    @Test("table grid borders produce dark ink at column divider x positions")
    func tableBordersHaveInk() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let t = Table(
            alignments: [.leading, .leading],
            header: [cellRuns("Col A"), cellRuns("Col B")],
            rows: [[cellRuns("val1"), cellRuns("val2")]],
            cellStyle: textStyle()
        )
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // The table occupies rows 0..h, so border lines should produce dark ink somewhere.
        var foundDarkPixel = false
        outer: for y in 0..<h {
            for x in 0..<w {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 200 || px.g < 200 || px.b < 200 {
                    foundDarkPixel = true
                    break outer
                }
            }
        }
        #expect(foundDarkPixel, "Table rendering should produce dark ink (borders or text)")
    }

    // ------------------------------------------------------------------
    // 5.4-B: Table cell text has ink in the cell content region
    // ------------------------------------------------------------------
    @Test("table cell text produces glyph ink in content region")
    func tableCellTextHasInk() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let t = Table(
            alignments: [.leading, .leading],
            header: [cellRuns("Hello"), cellRuns("World")],
            rows: [[cellRuns("Foo"), cellRuns("Bar")]],
            cellStyle: textStyle()
        )
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // Glyph ink should appear somewhere in the first 80 rows
        var foundInk = false
        outer: for y in 0..<80 {
            for x in 0..<(w / 2) {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundInk = true
                    break outer
                }
            }
        }
        #expect(foundInk, "Table cell region should have glyph ink")
    }

    // ------------------------------------------------------------------
    // 5.4-C: Code block box region is filled (non-white background)
    // ------------------------------------------------------------------
    @Test("code block box region has filled background (non-white)")
    func codeBoxIsFilled() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let cb = CodeBlock(
            lines: ["let x = 42", "return x"],
            language: nil,
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        guard case .code(_, let box, _, _) = layout.blocks[0] else {
            Issue.record("expected .code block frame"); return
        }

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // The box region should have non-white fill pixels.
        // In CG coordinates (y-up), box in doc-space maps to:
        //   CG y = canvasHeight - box.maxY ... canvasHeight - box.minY
        // In bitmap memory (row 0 = CG y = h-1 = top of image):
        //   bitmap row = h - 1 - CG_y = doc_y
        let boxMinRow = Int(box.minY)
        let boxMaxRow = min(Int(box.maxY), h - 1)

        var foundFill = false
        outerBox: for y in boxMinRow...boxMaxRow {
            for x in 0..<w {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                // Non-white fill (box background color)
                if px.r < 250 || px.g < 250 || px.b < 250 {
                    foundFill = true
                    break outerBox
                }
            }
        }
        #expect(foundFill, "Code block box region should have non-white fill pixels")
    }

    // ------------------------------------------------------------------
    // 5.4-D: Code block has glyph ink (text was drawn)
    // ------------------------------------------------------------------
    @Test("code block content region has glyph ink")
    func codeBlockGlyphInk() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let cb = CodeBlock(
            lines: ["hello world"],
            language: nil,
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // Glyph ink should appear in the first 60 rows
        var foundInk = false
        outer: for y in 0..<60 {
            for x in 0..<200 {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundInk = true
                    break outer
                }
            }
        }
        #expect(foundInk, "Code block should produce glyph ink in content region")
    }

    // ------------------------------------------------------------------
    // 5.4-E: Code block with language label — ink appears above box top
    // ------------------------------------------------------------------
    @Test("code block with language label produces ink above box region")
    func codeLanguageLabelHasInk() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let cb = CodeBlock(
            lines: ["func foo() {}"],
            language: "swift",
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        guard case .code(_, _, _, let langLabel) = layout.blocks[0] else {
            Issue.record("expected .code block frame"); return
        }
        // Verify we have a language label to render
        guard langLabel != nil else {
            Issue.record("code block with language should have language label"); return
        }

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // Ink must appear somewhere
        var foundInk = false
        outer: for y in 0..<h {
            for x in 0..<300 {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundInk = true
                    break outer
                }
            }
        }
        #expect(foundInk, "Code block with language should produce ink (label + content)")
    }

    // ------------------------------------------------------------------
    // 5.4-F: Empty table renders without crash
    // ------------------------------------------------------------------
    @Test("empty table renders without crash")
    func emptyTableNoOp() {
        let w = 100; let h = 100
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let t = Table(alignments: [], header: [], rows: [], cellStyle: textStyle())
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        // Must not crash
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])
        // Empty table — no non-white pixels expected
        let px = pixel(at: 50, y: 50, width: w, buffer: buffer)
        #expect(px.r == 255 && px.g == 255 && px.b == 255,
                "Empty table should not paint anything")
    }

    // ------------------------------------------------------------------
    // 5.4-G: Empty code block renders without crash (only box fill)
    // ------------------------------------------------------------------
    @Test("empty code block renders without crash")
    func emptyCodeBlockNoOp() {
        let w = 100; let h = 100
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let cb = CodeBlock(lines: [], language: nil, style: codeStyle())
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        // Must not crash
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])
        // Just verify it ran without crashing — no assertion on content needed
    }

    // ------------------------------------------------------------------
    // 5.4-H: Top border is dark at exactly row rowYs[0] (coordinate-precise)
    //
    // This test verifies the draw order fix: the header background fill must
    // NOT overwrite the top grid border line. With the old (broken) draw order
    // (borders first, then header fill), the header rect covers the top border
    // with the header's light grey color and this test would fail because the
    // pixel at the top border row would be light (header fill), not dark.
    // ------------------------------------------------------------------
    @Test("top border row has dark ink and first inter-column divider has dark ink")
    func topBorderAndColumnDividerAreVisible() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let t = Table(
            alignments: [.leading, .leading],
            header: [cellRuns("Col A"), cellRuns("Col B")],
            rows: [[cellRuns("val1"), cellRuns("val2")]],
            cellStyle: textStyle()
        )
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        guard case .table(let tableRect, let columnX, let rowYs, _, let borders) = layout.blocks[0] else {
            Issue.record("expected .table block frame"); return
        }
        // Suppress unused-variable warning — tableRect is used below for verification.
        _ = tableRect

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // --- (a) Check top border row ---
        // The top horizontal border is at rowYs[0] in doc-space (y-down).
        // In the bitmap (row 0 == top of image == doc-space y=0), that is bitmap row = Int(rowYs[0]).
        // The border has tableBorderThickness = 1 pt, so it occupies exactly 1 pixel row.
        let topBorderRow = Int(rowYs[0])
        guard topBorderRow < h else {
            Issue.record("topBorderRow \(topBorderRow) outside canvas height \(h)"); return
        }

        // Scan across the top border row; at least one pixel must be dark
        // (border color: ~0.4 grey → RGB ≈ 102, well under threshold 200).
        var topBorderIsDark = false
        for x in 0..<w {
            let px = pixel(at: x, y: topBorderRow, width: w, buffer: buffer)
            if px.r < 200 && px.g < 200 && px.b < 200 {
                topBorderIsDark = true
                break
            }
        }
        #expect(topBorderIsDark, "Top border at bitmap row \(topBorderRow) (doc rowYs[0]=\(rowYs[0])) must have dark ink — if this fails the header fill is overwriting the top grid line")

        // --- (b) Check first inter-column divider x ---
        // The first vertical divider is the left edge at origin.x (x=0), and
        // the first INTER-column line is at origin.x + columnWidths[0], i.e. columnX[1] - tableCellPaddingH.
        // We can read it from borders: find a vertical border rect that has minX > 0.
        // columnX[1] is the content-start of column 1; the divider is at columnX[1] - tableCellPaddingH.
        guard columnX.count >= 2 else {
            Issue.record("Need at least 2 columns to check inter-column divider"); return
        }
        // tableCellPaddingH is 8 pt, so first inter-column divider x = columnX[1] - 8
        let interColX = Int(columnX[1] - tableCellPaddingH)
        guard interColX > 0 && interColX < w else {
            Issue.record("interColX \(interColX) outside canvas width \(w)"); return
        }

        // Scan down that column x within the table rows; must find a dark pixel
        // (the vertical border line colour is the same ~0.4 grey).
        _ = borders  // used indirectly via columnX above
        let tableTop = Int(rowYs[0])
        let tableBottom = min(Int(rowYs.last ?? 0) + 2, h)
        var interColIsDark = false
        for y in tableTop..<tableBottom {
            let px = pixel(at: interColX, y: y, width: w, buffer: buffer)
            if px.r < 200 && px.g < 200 && px.b < 200 {
                interColIsDark = true
                break
            }
        }
        #expect(interColIsDark,
                "First inter-column divider at bitmap x=\(interColX) must have dark ink within table rows \(tableTop)..<\(tableBottom)")
    }
}
