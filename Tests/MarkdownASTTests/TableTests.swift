import Testing
@testable import MarkdownAST

@Suite("GFM tables (Pass A raw leaves)")
struct TableTests {
    @Test("simple two-column table")
    func simpleTable() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["| a | b |", "| - | - |", "| 1 | 2 |"],
            depth: 0
        )
        #expect(out == [
            .table(RawTable(
                alignments: [.none, .none],
                header: [["a", "b"]],
                rows: [["1", "2"]]
            ))
        ])
    }

    @Test("delimiter alignments: left, center, right")
    func tableAlignments() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["| a | b | c |", "|:--|:-:|--:|", "| 1 | 2 | 3 |"],
            depth: 0
        )
        #expect(out == [
            .table(RawTable(
                alignments: [.left, .center, .right],
                header: [["a", "b", "c"]],
                rows: [["1", "2", "3"]]
            ))
        ])
    }

    @Test("escaped pipe unescapes to a literal pipe inside the cell")
    func escapedPipe() {
        // Swift literal `"\\|"` is the two-char string `\|`.
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["| a \\| b | c |", "| - | - |"],
            depth: 0
        )
        #expect(out == [
            .table(RawTable(
                alignments: [.none, .none],
                header: [["a | b", "c"]],
                rows: []
            ))
        ])
    }

    @Test("tables cannot interrupt a paragraph (F7)")
    func tableRequiresBlankLineBefore() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["para", "| a |", "| - |"],
            depth: 0
        )
        #expect(out == [.paragraph(raw: "para\n| a |\n| - |")])
    }

    @Test("extra data cells are truncated to header width")
    func extraCellsNormalized() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["| a | b |", "| - | - |", "| 1 | 2 | 3 |"],
            depth: 0
        )
        #expect(out == [
            .table(RawTable(
                alignments: [.none, .none],
                header: [["a", "b"]],
                rows: [["1", "2"]]
            ))
        ])
    }

    @Test("missing data cells are padded with empty strings")
    func missingCellsPadded() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["| a | b |", "| - | - |", "| 1 |"],
            depth: 0
        )
        #expect(out == [
            .table(RawTable(
                alignments: [.none, .none],
                header: [["a", "b"]],
                rows: [["1", ""]]
            ))
        ])
    }

    @Test("table ends at a blank line; following text is a sibling paragraph")
    func tableEndsAtBlankLine() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["| a |", "| - |", "| 1 |", "", "after"],
            depth: 0
        )
        #expect(out == [
            .table(RawTable(
                alignments: [.none],
                header: [["a"]],
                rows: [["1"]]
            )),
            .paragraph(raw: "after")
        ])
    }

    @Test("table ends at a heading (block-start ends the table)")
    func tableEndsAtHeading() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["| a |", "| - |", "| 1 |", "# H"],
            depth: 0
        )
        #expect(out == [
            .table(RawTable(
                alignments: [.none],
                header: [["a"]],
                rows: [["1"]]
            )),
            .heading(level: 1, raw: "H")
        ])
    }

    @Test("invalid delimiter row falls through to a paragraph")
    func invalidDelimiterIsParagraph() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["| a | b |", "| - | x |", "| 1 | 2 |"],
            depth: 0
        )
        #expect(out == [.paragraph(raw: "| a | b |\n| - | x |\n| 1 | 2 |")])
    }

    @Test("leading and trailing pipes are optional")
    func noLeadingTrailingPipe() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["a | b", "- | -", "1 | 2"],
            depth: 0
        )
        #expect(out == [
            .table(RawTable(
                alignments: [.none, .none],
                header: [["a", "b"]],
                rows: [["1", "2"]]
            ))
        ])
    }

    @Test("2-space-indented table is recognised (0–3 leading spaces allowed)")
    func indentedTable() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["  | a | b |", "  | - | - |", "  | 1 | 2 |"],
            depth: 0
        )
        #expect(out == [
            .table(RawTable(
                alignments: [.none, .none],
                header: [["a", "b"]],
                rows: [["1", "2"]]
            ))
        ])
    }

    @Test("3-space indent is the upper bound for table indentation")
    func threeSpaceIndentTable() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["   | a |", "   | - |", "   | 1 |"],
            depth: 0
        )
        #expect(out == [
            .table(RawTable(
                alignments: [.none],
                header: [["a"]],
                rows: [["1"]]
            ))
        ])
    }

    @Test("4-space indent is NOT a table (it is indented code, T17)")
    func fourSpaceIndentNotTable() {
        // 4 leading spaces on the header ⇒ indented-code territory, not a table.
        // T17: ≥4-space lines are indented code (CommonMark §4.4); each line has
        // 4 leading spaces stripped, so the pipe rows become code content.
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["    | a |", "    | - |", "    | 1 |"],
            depth: 0
        )
        #expect(out == [.codeBlock(language: nil, code: "| a |\n| - |\n| 1 |")])
    }

    @Test("header/delimiter cell-count mismatch falls through to a paragraph")
    func countMismatchIsParagraph() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["| a | b | c |", "| - | - |", "| 1 | 2 | 3 |"],
            depth: 0
        )
        #expect(out == [.paragraph(raw: "| a | b | c |\n| - | - |\n| 1 | 2 | 3 |")])
    }
}
