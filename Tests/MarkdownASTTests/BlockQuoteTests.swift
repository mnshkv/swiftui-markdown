import Testing
@testable import MarkdownAST

@Suite("Block quotes (Pass A raw leaves)")
struct BlockQuoteTests {
    @Test("simple `> hello` becomes a quote wrapping a paragraph")
    func simpleQuote() {
        let out = BlockParser(defs: DefinitionStore()).parse(["> hello"], depth: 0)
        #expect(out == [.blockQuote(blocks: [.paragraph(raw: "hello")])])
    }

    @Test("`> > deep` nests two quotes")
    func nestedQuote() {
        let out = BlockParser(defs: DefinitionStore()).parse(["> > deep"], depth: 0)
        #expect(out == [.blockQuote(blocks: [.blockQuote(blocks: [.paragraph(raw: "deep")])])])
    }

    @Test("ATX heading inside a quote")
    func headingInsideQuote() {
        let out = BlockParser(defs: DefinitionStore()).parse(["> # H"], depth: 0)
        #expect(out == [.blockQuote(blocks: [.heading(level: 1, raw: "H")])])
    }

    @Test("heading after quote is a sibling, not inside the quote (K3 guard)")
    func headingSiblingNotInQuote() {
        let out = BlockParser(defs: DefinitionStore()).parse(["> para", "# H"], depth: 0)
        #expect(out == [.blockQuote(blocks: [.paragraph(raw: "para")]), .heading(level: 1, raw: "H")])
    }

    @Test("lazy continuation line is joined into the quote's paragraph")
    func lazyContinuationJoined() {
        let out = BlockParser(defs: DefinitionStore()).parse(["> para", "lazy"], depth: 0)
        #expect(out == [.blockQuote(blocks: [.paragraph(raw: "para\nlazy")])])
    }

    @Test("list marker after quote is a sibling paragraph (K3 guard; becomes list with T20)")
    func listSiblingNotInQuote() {
        let out = BlockParser(defs: DefinitionStore()).parse(["> para", "- item"], depth: 0)
        // At this wave lists are not yet parsed (T18/T20), so the sibling is a
        // paragraph. The key assertion: `- item` is NOT lazily joined into the
        // quote's paragraph. Once T20 lands this becomes `.list(...)`.
        #expect(out == [.blockQuote(blocks: [.paragraph(raw: "para")]), .paragraph(raw: "- item")])
    }

    @Test("a blank line without a marker ends the quote")
    func blankLineEndsQuote() {
        let out = BlockParser(defs: DefinitionStore()).parse(["> para", "", "after"], depth: 0)
        #expect(out == [.blockQuote(blocks: [.paragraph(raw: "para")]), .paragraph(raw: "after")])
    }

    @Test("`>` alone separates two paragraphs inside a quote")
    func twoParagraphsInQuote() {
        let out = BlockParser(defs: DefinitionStore()).parse(["> para", ">", "more"], depth: 0)
        #expect(out == [.blockQuote(blocks: [.paragraph(raw: "para"), .paragraph(raw: "more")])])
    }

    @Test("a blockquote interrupts a pending outer paragraph")
    func quoteInterruptsParagraph() {
        let out = BlockParser(defs: DefinitionStore()).parse(["outer", "> inner"], depth: 0)
        #expect(out == [.paragraph(raw: "outer"), .blockQuote(blocks: [.paragraph(raw: "inner")])])
    }

    @Test("up to 3 leading spaces are allowed before `>`")
    func threeSpaceIndentQuote() {
        let out = BlockParser(defs: DefinitionStore()).parse(["   > q"], depth: 0)
        #expect(out == [.blockQuote(blocks: [.paragraph(raw: "q")])])
    }

    @Test("4 leading spaces ⇒ not a quote (it is indented code, T17)")
    func fourSpaceIndentNotQuote() {
        // 4 leading spaces: not a blockquote marker. T17: ≥4-space lines are
        // indented code (CommonMark §4.4), so "    > q" becomes a code block
        // with content "> q" (4 leading spaces stripped).
        let out = BlockParser(defs: DefinitionStore()).parse(["    > q"], depth: 0)
        #expect(out == [.codeBlock(language: nil, code: "> q")])
    }

    @Test("`>hello` (no space) strips only the `>`")
    func noSpaceAfterMarker() {
        let out = BlockParser(defs: DefinitionStore()).parse([">hello"], depth: 0)
        #expect(out == [.blockQuote(blocks: [.paragraph(raw: "hello")])])
    }

    @Test("`>  hello` (two spaces) strips `>` and ONE space; paragraph trims the rest")
    func twoSpacesAfterMarker() {
        // Marker stripping: `>  hello` → inner ` hello` (one space stripped, one
        // remains). The paragraph accumulator then trims leading whitespace per
        // line (existing pre-T10 behavior), so the final paragraph raw is `hello`.
        let out = BlockParser(defs: DefinitionStore()).parse([">  hello"], depth: 0)
        #expect(out == [.blockQuote(blocks: [.paragraph(raw: "hello")])])
    }

    @Test("`>` alone yields an empty inner line (blank within quote)")
    func markerAloneIsEmptyInner() {
        // `>` alone with no continuation should produce an empty quote (no
        // paragraphs), since the only inner line is blank.
        let out = BlockParser(defs: DefinitionStore()).parse([">"], depth: 0)
        #expect(out == [.blockQuote(blocks: [])])
    }
}
