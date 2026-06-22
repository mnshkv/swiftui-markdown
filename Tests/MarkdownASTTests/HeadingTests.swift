import Testing
@testable import MarkdownAST

@Suite("ATX headings (Pass A raw leaves)")
struct HeadingTests {
    @Test("levels 1–6 parse with correct level and text")
    func headingLevels1to6() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["# H1", "## H2", "### H3", "#### H4", "##### H5", "###### H6"],
            depth: 0
        )
        #expect(out == [
            .heading(level: 1, raw: "H1"),
            .heading(level: 2, raw: "H2"),
            .heading(level: 3, raw: "H3"),
            .heading(level: 4, raw: "H4"),
            .heading(level: 5, raw: "H5"),
            .heading(level: 6, raw: "H6"),
        ])
    }

    @Test("closing hash run stripped when preceded by a space")
    func closingHashStrippedWithSpace() {
        let out = BlockParser(defs: DefinitionStore()).parse(["## Title ##"], depth: 0)
        #expect(out == [.heading(level: 2, raw: "Title")])
    }

    @Test("closing hash run kept when no space precedes it")
    func closingHashKeptWithoutPrecedingSpace() {
        let out = BlockParser(defs: DefinitionStore()).parse(["## foo###"], depth: 0)
        #expect(out == [.heading(level: 2, raw: "foo###")])
    }

    @Test("seven hashes is a paragraph, not a heading")
    func sevenHashesIsParagraph() {
        let out = BlockParser(defs: DefinitionStore()).parse(["####### nope"], depth: 0)
        #expect(out == [.paragraph(raw: "####### nope")])
    }

    @Test("four leading spaces is not a heading (falls through to paragraph)")
    func fourLeadingSpacesNotHeading() {
        // 4 leading spaces: stripUpTo3Spaces keeps them ⇒ not an ATX heading.
        // At this wave indented code is unimplemented, so the line falls through
        // to paragraph accumulation. The paragraph raw is the per-line trimmed
        // line ("    # H" trims to "# H").
        let out = BlockParser(defs: DefinitionStore()).parse(["    # H"], depth: 0)
        #expect(out == [.paragraph(raw: "# H")])
    }

    @Test("two leading spaces is still a heading")
    func twoLeadingSpacesIsHeading() {
        let out = BlockParser(defs: DefinitionStore()).parse(["  # H"], depth: 0)
        #expect(out == [.heading(level: 1, raw: "H")])
    }

    @Test("heading interrupts a pending paragraph")
    func headingInterruptsParagraph() {
        let out = BlockParser(defs: DefinitionStore()).parse(["para line", "# Heading"], depth: 0)
        #expect(out == [.paragraph(raw: "para line"), .heading(level: 1, raw: "Heading")])
    }

    @Test("empty heading and closing-hash-only heading yield empty raw")
    func emptyHeading() {
        let out1 = BlockParser(defs: DefinitionStore()).parse(["#"], depth: 0)
        #expect(out1 == [.heading(level: 1, raw: "")])

        let out2 = BlockParser(defs: DefinitionStore()).parse(["## #"], depth: 0)
        #expect(out2 == [.heading(level: 2, raw: "")])
    }

    @Test("heading text has surrounding whitespace trimmed")
    func headingTextTrimmed() {
        let out = BlockParser(defs: DefinitionStore()).parse(["#   spaced   "], depth: 0)
        #expect(out == [.heading(level: 1, raw: "spaced")])
    }
}