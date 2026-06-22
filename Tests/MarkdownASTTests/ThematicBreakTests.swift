import Testing
@testable import MarkdownAST

@Suite("Thematic breaks (Pass A raw leaves)")
struct ThematicBreakTests {
    @Test("`---` is a thematic break")
    func hrDashes() {
        let out = BlockParser(defs: DefinitionStore()).parse(["---"], depth: 0)
        #expect(out == [.thematicBreak])
    }

    @Test("`***` is a thematic break")
    func hrStars() {
        let out = BlockParser(defs: DefinitionStore()).parse(["***"], depth: 0)
        #expect(out == [.thematicBreak])
    }

    @Test("`___` is a thematic break")
    func hrUnderscores() {
        let out = BlockParser(defs: DefinitionStore()).parse(["___"], depth: 0)
        #expect(out == [.thematicBreak])
    }

    @Test("`- - -` is a thematic break")
    func hrSpacedDashes() {
        let out = BlockParser(defs: DefinitionStore()).parse(["- - -"], depth: 0)
        #expect(out == [.thematicBreak])
    }

    @Test("`* * *` is a thematic break")
    func hrSpacedStars() {
        let out = BlockParser(defs: DefinitionStore()).parse(["* * *"], depth: 0)
        #expect(out == [.thematicBreak])
    }

    @Test("`_ _ _` is a thematic break")
    func hrSpacedUnderscores() {
        let out = BlockParser(defs: DefinitionStore()).parse(["_ _ _"], depth: 0)
        #expect(out == [.thematicBreak])
    }

    @Test("`--` is a paragraph, not a thematic break")
    func twoDashesIsParagraph() {
        let out = BlockParser(defs: DefinitionStore()).parse(["--"], depth: 0)
        #expect(out == [.paragraph(raw: "--")])
    }

    @Test("four leading spaces is not a thematic break (it is indented code, T17)")
    func fourLeadingSpacesNotHr() {
        // 4 leading spaces: stripUpTo3Spaces keeps them ⇒ `stripped.first == " "`
        // ⇒ the 4-space gate rejects it as a thematic break. T17: ≥4-space lines
        // are indented code (CommonMark §4.4), so "    ---" becomes a code block
        // with content "---" (4 leading spaces stripped).
        let out = BlockParser(defs: DefinitionStore()).parse(["    ---"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "---")])
        #expect(out != [.thematicBreak])
    }

    @Test("three leading spaces is still a thematic break")
    func threeLeadingSpacesIsHr() {
        let out = BlockParser(defs: DefinitionStore()).parse(["   ---"], depth: 0)
        #expect(out == [.thematicBreak])
    }

    @Test("thematic break interrupts a pending paragraph")
    func hrInterruptsParagraph() {
        // Uses `***` (not `---`) to avoid the temporary setext-gap case
        // (`para\n---` is a setext underline per CommonMark, but setext is T16).
        let out = BlockParser(defs: DefinitionStore()).parse(["para", "***"], depth: 0)
        #expect(out == [.paragraph(raw: "para"), .thematicBreak])
    }

    @Test("thematic break between two paragraphs")
    func hrBetweenParagraphs() {
        let out = BlockParser(defs: DefinitionStore()).parse(["one", "***", "two"], depth: 0)
        #expect(out == [.paragraph(raw: "one"), .thematicBreak, .paragraph(raw: "two")])
    }
}