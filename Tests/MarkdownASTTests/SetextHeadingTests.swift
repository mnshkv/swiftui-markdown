import Testing
@testable import MarkdownAST

@Suite("Setext headings (Pass A raw leaves)")
struct SetextHeadingTests {
    @Test("`Title\\n===` is an h1")
    func setextH1() {
        let out = BlockParser(defs: DefinitionStore()).parse(["Title", "==="], depth: 0)
        #expect(out == [.heading(level: 1, raw: "Title")])
    }

    @Test("`Title\\n---` is an h2")
    func setextH2() {
        let out = BlockParser(defs: DefinitionStore()).parse(["Title", "---"], depth: 0)
        #expect(out == [.heading(level: 2, raw: "Title")])
    }

    @Test("a lone `---` (no pending paragraph) is a thematic break, not a heading")
    func loneDashIsThematicBreak() {
        // Regression guard for the T9 gap fix: with no pending paragraph text,
        // `---` is NOT a setext underline — it reaches the thematic-break branch.
        let out = BlockParser(defs: DefinitionStore()).parse(["---"], depth: 0)
        #expect(out == [.thematicBreak])
    }

    @Test("multi-line paragraph text + `===` is an h1 with joined text")
    func multiLineSetextH1() {
        let out = BlockParser(defs: DefinitionStore()).parse(["a", "b", "==="], depth: 0)
        #expect(out == [.heading(level: 1, raw: "a\nb")])
    }

    @Test("underline with 3 leading spaces is still a setext heading")
    func threeSpaceIndentOk() {
        let out = BlockParser(defs: DefinitionStore()).parse(["Title", "   ==="], depth: 0)
        #expect(out == [.heading(level: 1, raw: "Title")])
    }

    @Test("underline with 4 leading spaces is NOT setext (falls through to paragraph)")
    func fourSpaceIndentIsParagraph() {
        // 4 leading spaces: stripUpTo3Spaces keeps them ⇒ first char is a space
        // ⇒ rejected as a setext underline. At this wave indented code is
        // unimplemented (T17), so the line falls through to paragraph
        // accumulation. The paragraph flush appends each line via
        // `trimWhitespace`, which trims BOTH leading and trailing whitespace,
        // so "    ===" becomes "===" in the joined raw.
        let out = BlockParser(defs: DefinitionStore()).parse(["Title", "    ==="], depth: 0)
        #expect(out == [.paragraph(raw: "Title\n===")])
    }

    @Test("`para\\n---` is an h2, NOT paragraph + thematic break (T9 gap fix)")
    func paraThenDashIsHeadingNotThematic() {
        let out = BlockParser(defs: DefinitionStore()).parse(["para", "---"], depth: 0)
        #expect(out == [.heading(level: 2, raw: "para")])
        #expect(out != [.paragraph(raw: "para"), .thematicBreak])
    }

    @Test("setext heading after a completed paragraph")
    func setextAfterParagraph() {
        // A blank line ends `para1`; `Title` + `===` is a separate h1.
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["para1", "", "Title", "==="],
            depth: 0
        )
        #expect(out == [.paragraph(raw: "para1"), .heading(level: 1, raw: "Title")])
    }

    @Test("trailing whitespace on the underline is allowed")
    func setextH1TrailingWhitespace() {
        let out = BlockParser(defs: DefinitionStore()).parse(["Title", "===   "], depth: 0)
        #expect(out == [.heading(level: 1, raw: "Title")])
    }
}