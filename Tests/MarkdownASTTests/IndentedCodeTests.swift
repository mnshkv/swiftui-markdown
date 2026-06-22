import Testing
@testable import MarkdownAST

@Suite("Indented code blocks (Pass A raw leaves, CommonMark §4.4)")
struct IndentedCodeTests {
    @Test("basic indented code: strip 4 spaces from each content line")
    func basicIndentedCode() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["    let x = 1", "    let y = 2"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "let x = 1\nlet y = 2")])
    }

    @Test("cannot interrupt a paragraph: indented line is lazy continuation")
    func cannotInterruptParagraph() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["text", "    more"], depth: 0)
        // `    more` → trimWhitespace → `more`; joins pending as "text\nmore".
        #expect(out == [.paragraph(raw: "text\nmore")])
    }

    @Test("internal blank line is preserved as an empty content line")
    func internalBlankPreserved() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["    foo", "", "    bar"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "foo\n\nbar")])
    }

    @Test("trailing blanks are trimmed; following dedented line is a sibling")
    func trailingBlanksTrimmed() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["    foo", "", "", "bar"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "foo"), .paragraph(raw: "bar")])
    }

    @Test("trailing blank at EOF is not included in code")
    func trailingBlankAtEOF() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["    foo", ""], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "foo")])
    }

    @Test("4-space `---` is indented code, not a thematic break")
    func fourSpaceThematicIsCode() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["    ---"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "---")])
    }

    @Test("4-space `# H` is indented code (fixes T8 gap)")
    func fourSpaceAtxIsCode() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["    # H"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "# H")])
    }

    @Test("4-space fence-looking lines are code content, not a fenced block")
    func fourSpaceFenceIsCode() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["    ```", "    code", "    ```"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "```\ncode\n```")])
    }

    @Test("regression: 0-space `---` is still a thematic break")
    func zeroSpaceThematicUnchanged() {
        let out = BlockParser(defs: DefinitionStore()).parse(["---"], depth: 0)
        #expect(out == [.thematicBreak])
    }

    @Test("regression: 3-space `---` is still a thematic break")
    func threeSpaceThematicUnchanged() {
        let out = BlockParser(defs: DefinitionStore()).parse(["   ---"], depth: 0)
        #expect(out == [.thematicBreak])
    }

    @Test("5-space indent: strip 4, keep 1")
    func fiveSpaceIndent() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["     foo"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: " foo")])
    }

    @Test("multiple internal blanks each become their own empty content line")
    func multipleInternalBlanks() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["    foo", "", "", "    bar"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "foo\n\n\nbar")])
    }

    @Test("indented code followed by a dedented paragraph sibling")
    func indentedCodeThenParagraph() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["    foo", "bar"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "foo"), .paragraph(raw: "bar")])
    }
}
