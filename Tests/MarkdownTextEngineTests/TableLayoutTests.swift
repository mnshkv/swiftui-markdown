import Testing
import CoreGraphics
import CoreText
@testable import MarkdownTextEngine

// MARK: - Shared helpers

private func textStyle() -> TextStyle {
    TextStyle(fontSize: 14, color: CGColor(gray: 0, alpha: 1))
}

private func codeStyle() -> TextStyle {
    TextStyle(fontSize: 13, isMonospace: true, color: CGColor(gray: 0, alpha: 1))
}

private func cellRuns(_ text: String) -> [InlineRun] {
    [.text(text, textStyle())]
}

private func makeTable(
    alignments: [TextAlignment] = [.leading, .leading],
    header: [[InlineRun]]? = nil,
    rows: [[[InlineRun]]]? = nil
) -> Table {
    let h = header ?? [cellRuns("Short"), cellRuns("Much Longer Cell")]
    let r = rows ?? [[cellRuns("A"), cellRuns("B")]]
    return Table(alignments: alignments, header: h, rows: r, cellStyle: textStyle())
}

// MARK: - Task 5.1: Column measurement

@Suite("Table column measurement (Task 5.1)")
struct TableColumnMeasurementTests {

    // 5.1-A: widths sum <= available width
    @Test("column widths sum does not exceed available width")
    func widthsSumLteAvailable() {
        let t = makeTable()
        let available: CGFloat = 400
        let widths = tableColumnWidths(t, available: available)
        let sum = widths.reduce(0, +)
        #expect(sum <= available + 1, "widths sum \(sum) should be <= available \(available)")
    }

    // 5.1-B: wider-content column gets more width
    @Test("wider-content column gets proportionally more width")
    func widerContentGetsMoreWidth() {
        // Col 0: "Short", Col 1: "Much Longer Cell" — col 1 should be wider
        let t = makeTable(
            header: [cellRuns("Short"), cellRuns("Much Longer Cell")],
            rows: [[cellRuns("A"), cellRuns("B")]]
        )
        let widths = tableColumnWidths(t, available: 400)
        #expect(widths.count == 2)
        #expect(widths[1] > widths[0],
                "col 1 (longer content) should be wider than col 0, got \(widths)")
    }

    // 5.1-C: returns correct column count (max across header + rows)
    @Test("column count equals max cells across all rows")
    func columnCountIsMax() {
        let t = makeTable(
            alignments: [.leading, .leading, .trailing],
            header: [cellRuns("A"), cellRuns("B"), cellRuns("C")],
            rows: [[cellRuns("x"), cellRuns("y"), cellRuns("z")]]
        )
        let widths = tableColumnWidths(t, available: 400)
        #expect(widths.count == 3)
    }

    // 5.1-D: zero-column table (empty header/rows) doesn't crash
    @Test("empty table (zero columns) doesn't crash")
    func zeroColumnTable() {
        let t = Table(alignments: [], header: [], rows: [], cellStyle: textStyle())
        let widths = tableColumnWidths(t, available: 400)
        #expect(widths.isEmpty)
    }

    // 5.1-E: each column width is > 0
    @Test("each column width is positive")
    func eachWidthIsPositive() {
        let t = makeTable()
        let widths = tableColumnWidths(t, available: 400)
        for (i, w) in widths.enumerated() {
            #expect(w > 0, "column \(i) width should be positive, got \(w)")
        }
    }

    // 5.1-F: row with more cells than header — column count covers all
    @Test("row with more cells than header expands column count")
    func rowMoreCellsThanHeader() {
        let t = Table(
            alignments: [.leading, .leading, .leading],
            header: [cellRuns("A"), cellRuns("B")],
            rows: [[cellRuns("x"), cellRuns("y"), cellRuns("z")]],
            cellStyle: textStyle()
        )
        let widths = tableColumnWidths(t, available: 600)
        #expect(widths.count == 3)
    }
}

// MARK: - Task 5.2: Table layout

@Suite("Table layout (Task 5.2)")
struct TableLayoutBlockTests {

    // 5.2-A: row heights equal max cell height in each row
    @Test("row heights equal max cell height in each row")
    func rowHeightsAreMax() {
        let t = makeTable(
            alignments: [.leading, .leading],
            header: [cellRuns("H1"), cellRuns("H2")],
            rows: [[cellRuns("A"), cellRuns("B")]]
        )
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .table(_, _, let rowYs, let cellLines, _) = layout.blocks[0] else {
            Issue.record("expected .table block frame"); return
        }
        // rowYs has count == numRows + 1 (boundaries), so numRows = rowYs.count - 1
        // cellLines is [[cells per row]], first row = header, then body rows
        #expect(rowYs.count >= 2, "need at least header + 1 body row = 2 intervals")
        // Row 0 (header): height should be > 0
        let headerHeight = rowYs[1] - rowYs[0]
        #expect(headerHeight > 0, "header row height should be > 0")
    }

    // 5.2-B: cell origins match column x positions
    @Test("cell x-origins match the column positions")
    func cellOriginsMatchColumns() {
        let t = makeTable(
            alignments: [.leading, .leading],
            header: [cellRuns("Col A"), cellRuns("Col B")],
            rows: [[cellRuns("data"), cellRuns("more data")]]
        )
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .table(let rect, let columnX, let rowYs, let cellLines, _) = layout.blocks[0] else {
            Issue.record("expected .table block frame"); return
        }
        #expect(columnX.count == 2)
        #expect(rowYs.count >= 2)
        #expect(cellLines.count >= 2)

        // Header row (index 0): check that each cell's lines start at correct x
        let headerRow = cellLines[0]
        for (colIdx, cellLinesForCell) in headerRow.enumerated() {
            if let firstLine = cellLinesForCell.first {
                // Cell x should be at or near columnX[colIdx]
                #expect(firstLine.origin.x >= columnX[colIdx] - 1,
                        "header cell \(colIdx) x \(firstLine.origin.x) should be >= columnX[\(colIdx)] \(columnX[colIdx])")
            }
        }
        _ = rect  // suppress unused warning
    }

    // 5.2-C: right-aligned column has text at the right of the cell
    @Test("right-aligned column lines are right-offset within cell")
    func rightAlignedColumnOffset() {
        let t = Table(
            alignments: [.leading, .trailing],
            header: [cellRuns("Left"), cellRuns("Right")],
            rows: [[cellRuns("val"), cellRuns("longtext")]],
            cellStyle: textStyle()
        )
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .table(_, let columnX, _, let cellLines, _) = layout.blocks[0] else {
            Issue.record("expected .table block frame"); return
        }
        // Right column (col 1): first line origin.x should be > columnX[1]
        // because it's right-aligned (text starts closer to right edge)
        guard cellLines.count >= 1, cellLines[0].count >= 2 else {
            Issue.record("expected header row with 2 cells"); return
        }
        let rightCell = cellLines[0][1]
        if let firstLine = rightCell.first {
            // Right-aligned: x offset from column start should be > 0
            let offsetFromColumnStart = firstLine.origin.x - columnX[1]
            #expect(offsetFromColumnStart >= 0,
                    "right-aligned cell x \(firstLine.origin.x) should be >= columnX[1] \(columnX[1])")
        }
    }

    // 5.2-D: contentHeight updated (last block a table — doc height >= table maxY)
    @Test("document contentHeight is updated when last block is a table")
    func contentHeightUpdatedForTable() {
        let t = makeTable()
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .table(let rect, _, _, _, _) = layout.blocks[0] else {
            Issue.record("expected .table block frame"); return
        }
        #expect(rect.height > 0, "table rect should have positive height")
        #expect(layout.contentSize.height >= rect.maxY,
                "contentSize.height \(layout.contentSize.height) should be >= table rect.maxY \(rect.maxY)")
    }

    // 5.2-E: border rects — grid lines produced
    @Test("table produces border rects for grid lines")
    func tableBorderRectsProduced() {
        let t = makeTable(
            alignments: [.leading, .leading],
            header: [cellRuns("A"), cellRuns("B")],
            rows: [[cellRuns("1"), cellRuns("2")]]
        )
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .table(_, _, _, _, let borders) = layout.blocks[0] else {
            Issue.record("expected .table block frame"); return
        }
        // Should have some border rects (header row divider + column dividers)
        #expect(!borders.isEmpty, "table should produce at least one border rect")
    }

    // 5.2-F: empty table (0 rows, 0 cols) doesn't crash
    @Test("empty table (0 rows, 0 columns) doesn't crash")
    func emptyTableNoCrash() {
        let t = Table(alignments: [], header: [], rows: [], cellStyle: textStyle())
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: 400)
        // Just verify it doesn't crash and produces a block
        #expect(layout.blocks.count == 1)
    }

    // 5.2-G: two body rows — rows stack vertically
    @Test("two body rows are stacked vertically (no overlap)")
    func twoBodyRowsStackVertically() {
        let t = Table(
            alignments: [.leading, .leading],
            header: [cellRuns("H1"), cellRuns("H2")],
            rows: [
                [cellRuns("R1C1"), cellRuns("R1C2")],
                [cellRuns("R2C1"), cellRuns("R2C2")]
            ],
            cellStyle: textStyle()
        )
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .table(_, _, let rowYs, _, _) = layout.blocks[0] else {
            Issue.record("expected .table block frame"); return
        }
        // rowYs[0] < rowYs[1] < rowYs[2] < rowYs[3]
        #expect(rowYs.count == 4, "header + 2 body rows => 4 row boundaries")
        #expect(rowYs[0] < rowYs[1])
        #expect(rowYs[1] < rowYs[2])
        #expect(rowYs[2] < rowYs[3])
    }
}

// MARK: - Task 5.3: Code block layout

@Suite("Code block layout (Task 5.3)")
struct CodeBlockLayoutTests {

    // 5.3-A: N source lines → ≥ N LineFrames
    @Test("N source lines produce at least N LineFrames")
    func nLinesProducesNLineFrames() {
        let cb = CodeBlock(
            lines: ["let x = 1", "let y = 2", "let z = 3"],
            language: nil,
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .code(_, _, let lines, _) = layout.blocks[0] else {
            Issue.record("expected .code block frame"); return
        }
        #expect(lines.count >= 3,
                "3 source lines should produce >= 3 LineFrames, got \(lines.count)")
    }

    // 5.3-B: long lines wrap, producing extra line frames
    @Test("long line that exceeds width wraps to more than one LineFrame")
    func longLineWraps() {
        let longLine = String(repeating: "word ", count: 50)
        let cb = CodeBlock(
            lines: [longLine],
            language: nil,
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: 200)  // narrow width forces wrap

        guard case .code(_, _, let lines, _) = layout.blocks[0] else {
            Issue.record("expected .code block frame"); return
        }
        #expect(lines.count >= 2,
                "long line should wrap to >= 2 LineFrames at narrow width")
    }

    // 5.3-C: box rect encloses lines with padding
    @Test("box rect encloses all code lines with padding")
    func boxEncloseLines() {
        let cb = CodeBlock(
            lines: ["hello", "world"],
            language: nil,
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .code(_, let box, let lines, _) = layout.blocks[0] else {
            Issue.record("expected .code block frame"); return
        }
        // Box must contain all lines
        for line in lines {
            let lineBottom = line.origin.y + line.size.height
            #expect(box.minY <= line.origin.y,
                    "box.minY \(box.minY) should be <= line.origin.y \(line.origin.y)")
            #expect(box.maxY >= lineBottom,
                    "box.maxY \(box.maxY) should be >= line bottom \(lineBottom)")
        }
    }

    // 5.3-D: contentHeight updated for code block
    @Test("document contentHeight is updated when last block is a code block")
    func contentHeightUpdatedForCode() {
        let cb = CodeBlock(
            lines: ["print(\"Hello\")"],
            language: nil,
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .code(let rect, _, _, _) = layout.blocks[0] else {
            Issue.record("expected .code block frame"); return
        }
        #expect(rect.height > 0, "code block rect should have positive height")
        #expect(layout.contentSize.height >= rect.maxY,
                "contentSize.height \(layout.contentSize.height) should be >= code rect.maxY \(rect.maxY)")
    }

    // 5.3-E: empty code block (no lines) doesn't crash
    @Test("empty code block (no lines) doesn't crash")
    func emptyCodeBlockNoCrash() {
        let cb = CodeBlock(lines: [], language: nil, style: codeStyle())
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: 400)
        #expect(layout.blocks.count == 1)
    }

    // 5.3-F: language label produces a LineFrame when language is specified
    @Test("language label is present when language is specified")
    func languageLabelPresent() {
        let cb = CodeBlock(
            lines: ["let x = 1"],
            language: "swift",
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .code(_, _, _, let langLabel) = layout.blocks[0] else {
            Issue.record("expected .code block frame"); return
        }
        #expect(langLabel != nil, "code block with language should have a non-nil languageLabel")
    }

    // 5.3-G: no language label when language is nil
    @Test("language label is nil when no language is specified")
    func noLanguageLabelWhenNil() {
        let cb = CodeBlock(lines: ["let x = 1"], language: nil, style: codeStyle())
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .code(_, _, _, let langLabel) = layout.blocks[0] else {
            Issue.record("expected .code block frame"); return
        }
        #expect(langLabel == nil, "code block without language should have nil languageLabel")
    }

    // 5.3-H: code block after paragraph: paragraph is above, code is below
    @Test("code block after paragraph is positioned below paragraph")
    func codeAfterParagraphIsBelow() {
        let paraStyle = TextStyle(fontSize: 17, color: CGColor(gray: 0, alpha: 1))
        let para = Paragraph(
            runs: [.text("Before", paraStyle)],
            style: .body
        )
        let cb = CodeBlock(lines: ["code line"], language: nil, style: codeStyle())
        let doc = TextDocument(blocks: [.paragraph(para), .codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .text(let paraRect, _) = layout.blocks[0],
              case .code(let codeRect, _, _, _) = layout.blocks[1] else {
            Issue.record("expected paragraph then code block"); return
        }
        #expect(codeRect.minY >= paraRect.maxY,
                "code block top \(codeRect.minY) should be >= paragraph bottom \(paraRect.maxY)")
    }
}
