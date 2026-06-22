import Testing
@testable import MarkdownAST

@Suite("Fenced code blocks (Pass A raw leaves)")
struct FencedCodeTests {
    @Test("backtick fence emits a code block")
    func backtickFence() {
        let out = BlockParser(defs: DefinitionStore()).parse(["```", "code", "```"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "code")])
    }

    @Test("tilde fence emits a code block")
    func tildeFence() {
        let out = BlockParser(defs: DefinitionStore()).parse(["~~~", "code", "~~~"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "code")])
    }

    @Test("info string first word becomes language")
    func infoStringIsLanguage() {
        let out = BlockParser(defs: DefinitionStore()).parse(["```swift", "let x = 1", "```"], depth: 0)
        #expect(out == [.codeBlock(language: "swift", code: "let x = 1")])
    }

    @Test("info string trailing spaces are stripped before language extraction")
    func infoStringTrailingSpacesStripped() {
        let out = BlockParser(defs: DefinitionStore()).parse(["```x   ", "c", "```"], depth: 0)
        #expect(out == [.codeBlock(language: "x", code: "c")])
    }

    @Test("`# not a heading` inside a fence is literal content")
    func hashInsideIsLiteral() {
        let out = BlockParser(defs: DefinitionStore()).parse(["```", "# not a heading", "```"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "# not a heading")])
    }

    @Test("unclosed fence runs to EOF")
    func unclosedRunsToEof() {
        let out = BlockParser(defs: DefinitionStore()).parse(["```", "code", "more"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "code\nmore")])
    }

    @Test("opening indent is stripped from each content line")
    func indentStrippedFromContent() {
        let out = BlockParser(defs: DefinitionStore()).parse(["   ```", "   code", "   ```"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "code")])
    }

    @Test("closing fence shorter than opening is content (block runs to EOF)")
    func closingFenceShorterIsContent() {
        let out = BlockParser(defs: DefinitionStore()).parse(["````", "code", "```"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "code\n```")])
    }

    @Test("trailing whitespace after the closing fence is allowed")
    func trailingSpacesAfterClosingFenceAllowed() {
        let out = BlockParser(defs: DefinitionStore()).parse(["```", "code", "```   "], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "code")])
    }

    @Test("non-whitespace after the closing-fence run makes it content (runs to EOF)")
    func closingFenceWithContentAfterIsNotCloser() {
        let out = BlockParser(defs: DefinitionStore()).parse(["```", "code", "```x"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "code\n```x")])
    }

    @Test("fenced code interrupts a pending paragraph")
    func fenceInterruptsParagraph() {
        let out = BlockParser(defs: DefinitionStore()).parse(["para", "```", "code", "```"], depth: 0)
        #expect(out == [.paragraph(raw: "para"), .codeBlock(language: nil, code: "code")])
    }

    @Test("four leading spaces is NOT a fence (falls through to paragraph)")
    func fourLeadingSpacesNotFence() {
        // 4 leading spaces ⇒ not a fence opener (indented-code territory, T17).
        // At this wave indented code isn't implemented, so each line falls through
        // to paragraph accumulation. T7 trims each line: "    ```" → "```",
        // "    code" → "code", "    ```" → "```". Joined into one paragraph.
        let out = BlockParser(defs: DefinitionStore()).parse(["    ```", "    code", "    ```"], depth: 0)
        #expect(out == [.paragraph(raw: "```\ncode\n```")])
    }

    @Test("blank line inside a fenced code block is preserved as empty content")
    func blankLineInsideCode() {
        let out = BlockParser(defs: DefinitionStore()).parse(["```", "code", "", "more", "```"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "code\n\nmore")])
    }
}