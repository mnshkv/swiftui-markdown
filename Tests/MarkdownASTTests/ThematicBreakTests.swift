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

    @Test("`*  *  *` (multi-space) is a thematic break")
    func hrMultiSpaceStars() {
        // Closes the Task 9 nit: "no `*  *  *` multi-space test". A thematic
        // break allows any number of spaces between the repeat chars
        // (CommonMark §4.2). Verified via the FULL dispatcher so the Task 19
        // ordering guard locks this behavior against the future Task 20 list
        // branch — `*  *  *` must remain `.thematicBreak`, not a list.
        let out = BlockParser(defs: DefinitionStore()).parse(["*  *  *"], depth: 0)
        #expect(out == [.thematicBreak])
    }

    @Test("`- - - -` (four-dash run) is a thematic break")
    func hrFourSpacedDashes() {
        // A thematic break is ≥3 repeat chars separated by ≤3 spaces
        // (CommonMark §4.2); 4 `-` chars is still a break. Verified via the
        // full dispatcher as a Task 19 regression guard against the future
        // list branch.
        let out = BlockParser(defs: DefinitionStore()).parse(["- - - -"], depth: 0)
        #expect(out == [.thematicBreak])
    }

    @Test("`- a` is a single-item bullet list (not a thematic break)")
    func dashAIsList() {
        // `- a` is a bullet list item, distinct from the thematic-break-shaped
        // `- - -`; the list branch (T20) sits below the thematic-break branch.
        let out = BlockParser(defs: DefinitionStore()).parse(["- a"], depth: 0)
        #expect(out == [
            .list(RawList(kind: .bullet, isTight: true, items: [
                RawListItem(blocks: [.paragraph(raw: "a")], task: nil),
            ])),
        ])
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
