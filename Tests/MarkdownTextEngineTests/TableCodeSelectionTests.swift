import Testing
import CoreGraphics
import CoreText
@testable import MarkdownTextEngine

// MARK: - Helpers

private func textStyle() -> TextStyle {
    TextStyle(fontSize: 14, color: CGColor(gray: 0, alpha: 1))
}

private func codeStyle() -> TextStyle {
    TextStyle(fontSize: 13, isMonospace: true, color: CGColor(gray: 0, alpha: 1))
}

private func cellRuns(_ text: String) -> [InlineRun] {
    [.text(text, textStyle())]
}

private func paraBlock(_ text: String) -> Block {
    .paragraph(Paragraph(runs: [.text(text, textStyle())], style: .body))
}

// MARK: - Task 5.5: Selection through tables and code blocks

@Suite("Selection through tables and code (Task 5.5)")
struct TableCodeSelectionTests {

    // ------------------------------------------------------------------
    // Convention: flattenedText for tables
    // Cells joined with "\t", rows joined with "\n" (header first).
    // ------------------------------------------------------------------

    // 5.5-A: flattenedText for a 2-column table
    @Test("flattenedText for a 2-column table uses tab-separated cells and newline-separated rows")
    func flattenedTextTable() {
        let t = Table(
            alignments: [.leading, .leading],
            header: [cellRuns("H1"), cellRuns("H2")],
            rows: [[cellRuns("A"), cellRuns("B")]],
            cellStyle: textStyle()
        )
        let doc = TextDocument(blocks: [.table(t)])
        let flat = flattenedText(doc)
        // Convention: header row: "H1\tH2", body row: "A\tB", joined with "\n"
        #expect(flat == "H1\tH2\nA\tB",
                "table flattened text should be 'H1\\tH2\\nA\\tB', got '\(flat)'")
    }

    // 5.5-B: flattenedText for a table with 3 body rows
    @Test("flattenedText for table with 3 rows — all rows separated by newline")
    func flattenedTextTableMultipleRows() {
        let t = Table(
            alignments: [.leading, .leading],
            header: [cellRuns("Name"), cellRuns("Age")],
            rows: [
                [cellRuns("Alice"), cellRuns("30")],
                [cellRuns("Bob"), cellRuns("25")],
                [cellRuns("Eve"), cellRuns("28")]
            ],
            cellStyle: textStyle()
        )
        let doc = TextDocument(blocks: [.table(t)])
        let flat = flattenedText(doc)
        #expect(flat == "Name\tAge\nAlice\t30\nBob\t25\nEve\t28",
                "multi-row table flat text mismatch: '\(flat)'")
    }

    // 5.5-C: flattenedText for code block — lines joined with "\n"
    @Test("flattenedText for code block joins lines with newline")
    func flattenedTextCodeBlock() {
        let cb = CodeBlock(
            lines: ["let x = 1", "let y = 2", "return x + y"],
            language: nil,
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let flat = flattenedText(doc)
        #expect(flat == "let x = 1\nlet y = 2\nreturn x + y",
                "code block flat text should be lines joined by '\\n', got '\(flat)'")
    }

    // 5.5-D: copyText spanning two table cells returns both cells' text with separator
    @Test("copyText spanning two cells returns both cells with tab separator")
    func copyTextSpansTwoCells() {
        let t = Table(
            alignments: [.leading, .leading],
            header: [cellRuns("Name"), cellRuns("Value")],
            rows: [],
            cellStyle: textStyle()
        )
        let doc = TextDocument(blocks: [.table(t)])
        let flat = flattenedText(doc)
        // flat = "Name\tValue"
        #expect(flat == "Name\tValue")
        let range = TextRange(
            start: TextPosition(index: 0),
            end: TextPosition(index: flat.utf16.count)
        )
        let copied = copyText(for: range, doc: doc)
        #expect(copied == "Name\tValue",
                "copyText should return 'Name\\tValue', got '\(copied)'")
    }

    // 5.5-E: copyText spanning two rows returns rows joined by newline
    @Test("copyText spanning two table rows returns rows joined by newline")
    func copyTextSpansTwoRows() {
        let t = Table(
            alignments: [.leading, .leading],
            header: [cellRuns("H1"), cellRuns("H2")],
            rows: [[cellRuns("A"), cellRuns("B")]],
            cellStyle: textStyle()
        )
        let doc = TextDocument(blocks: [.table(t)])
        let flat = flattenedText(doc)
        // flat = "H1\tH2\nA\tB"
        let range = TextRange(
            start: TextPosition(index: 0),
            end: TextPosition(index: flat.utf16.count)
        )
        let copied = copyText(for: range, doc: doc)
        #expect(copied == "H1\tH2\nA\tB",
                "copyText spanning both rows should return 'H1\\tH2\\nA\\tB', got '\(copied)'")
    }

    // 5.5-F: copyText across code lines returns lines joined by "\n"
    @Test("copyText across code lines returns lines joined by newline")
    func copyTextAcrossCodeLines() {
        let cb = CodeBlock(
            lines: ["line one", "line two"],
            language: nil,
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let flat = flattenedText(doc)
        // flat = "line one\nline two"
        let range = TextRange(
            start: TextPosition(index: 0),
            end: TextPosition(index: flat.utf16.count)
        )
        let copied = copyText(for: range, doc: doc)
        #expect(copied == "line one\nline two",
                "copyText across code lines should be 'line one\\nline two', got '\(copied)'")
    }

    // 5.5-G: selectionRects spanning two table cells returns rects in both cells
    @Test("selectionRects spanning two cells returns rects in both cells")
    func selectionRectsSpansTwoCells() {
        let t = Table(
            alignments: [.leading, .leading],
            header: [cellRuns("Cell One"), cellRuns("Cell Two")],
            rows: [],
            cellStyle: textStyle()
        )
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: 400)
        let flat = flattenedText(doc)
        // flat = "Cell One\tCell Two"
        let range = TextRange(
            start: TextPosition(index: 0),
            end: TextPosition(index: flat.utf16.count)
        )
        let rects = selectionRects(for: range, in: layout, doc: doc)
        #expect(rects.count >= 2,
                "Selection spanning two cells should return >= 2 rects, got \(rects.count)")
    }

    // 5.5-H: selectionRects for a selection inside first code line
    @Test("selectionRects for selection inside first code line returns non-empty rects")
    func selectionRectsInsideCodeLine() {
        let cb = CodeBlock(
            lines: ["hello world"],
            language: nil,
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: 400)
        let flat = flattenedText(doc)
        // flat = "hello world"
        let range = TextRange(
            start: TextPosition(index: 0),
            end: TextPosition(index: "hello".utf16.count)
        )
        let rects = selectionRects(for: range, in: layout, doc: doc)
        #expect(!rects.isEmpty, "Selection inside code line should return non-empty rects")
    }

    // 5.5-I: hit-test into second table row maps to position in that row
    @Test("hit-test into second table row returns position inside second row")
    func hitTestInSecondTableRow() {
        let t = Table(
            alignments: [.leading, .leading],
            header: [cellRuns("H1"), cellRuns("H2")],
            rows: [[cellRuns("Row1"), cellRuns("Data")]],
            cellStyle: textStyle()
        )
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .table(_, _, let rowYs, let cellLines, _) = layout.blocks[0],
              rowYs.count >= 3 else {
            Issue.record("expected table with header + 1 body row"); return
        }

        // Find the y-center of the second row (body row, index 1 in rowYs)
        let row1Y = (rowYs[1] + rowYs[2]) / 2
        guard cellLines.count >= 2, !cellLines[1].isEmpty,
              let firstCellLine = cellLines[1][0].first else {
            Issue.record("expected body row with cell lines"); return
        }

        let hitPoint = CGPoint(x: firstCellLine.origin.x + 5, y: row1Y)
        let pos = position(at: hitPoint, in: layout, doc: doc)

        // "H1\tH2\nRow1\tData"
        // Header = "H1\tH2" = 5 UTF-16 units, then "\n" separator, body starts at 6
        let headerRowText = "H1\tH2"
        let bodyRowStart = headerRowText.utf16.count + 1  // +1 for "\n"
        #expect(pos.index >= bodyRowStart,
                "Hit in body row should yield index >= \(bodyRowStart), got \(pos.index)")
    }

    // 5.5-J: selectionRects spanning two code lines returns rects in both lines
    @Test("selectionRects spanning two code lines returns rects in both")
    func selectionRectsSpansTwoCodeLines() {
        let cb = CodeBlock(
            lines: ["first line", "second line"],
            language: nil,
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: 400)
        let flat = flattenedText(doc)
        // flat = "first line\nsecond line"
        let range = TextRange(
            start: TextPosition(index: 0),
            end: TextPosition(index: flat.utf16.count)
        )
        let rects = selectionRects(for: range, in: layout, doc: doc)
        #expect(rects.count >= 2,
                "Selection spanning 2 code lines should return >= 2 rects, got \(rects.count)")
        if rects.count >= 2 {
            #expect(rects[0].origin.y <= rects[1].origin.y,
                    "First code line rect should be at or above second line rect")
        }
    }

    // 5.5-K: table after paragraph — UTF-16 bases are correct
    @Test("UTF-16 bases correct for paragraph then table")
    func utf16BasesForParagraphThenTable() {
        let t = Table(
            alignments: [.leading],
            header: [cellRuns("A")],
            rows: [],
            cellStyle: textStyle()
        )
        let doc = TextDocument(blocks: [paraBlock("Intro"), .table(t)])
        let bases = utf16Bases(for: doc)
        let flat = flattenedText(doc)
        // flat = "Intro\nA"
        #expect(flat == "Intro\nA", "flat text mismatch: '\(flat)'")
        #expect(bases.count == 2)
        #expect(bases[0] == 0)
        #expect(bases[1] == 6, "table base should be 6 (= 'Intro'.utf16.count + 1)")
    }

    // 5.5-L: code block after paragraph — UTF-16 bases are correct
    @Test("UTF-16 bases correct for paragraph then code block")
    func utf16BasesForParagraphThenCode() {
        let cb = CodeBlock(lines: ["x", "y"], language: nil, style: codeStyle())
        let doc = TextDocument(blocks: [paraBlock("Pre"), .codeBlock(cb)])
        let bases = utf16Bases(for: doc)
        let flat = flattenedText(doc)
        // flat = "Pre\nx\ny"
        #expect(flat == "Pre\nx\ny", "flat text mismatch: '\(flat)'")
        #expect(bases.count == 2)
        #expect(bases[0] == 0)
        #expect(bases[1] == 4, "code base should be 4 (= 'Pre'.utf16.count + 1)")
    }
}
