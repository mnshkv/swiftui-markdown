import Testing
@testable import MarkdownAST

@Suite("Paragraph (Pass A raw leaves)")
struct ParagraphTests {
    @Test("single line becomes one paragraph")
    func singleParagraph() {
        let out = BlockParser(defs: DefinitionStore()).parse(["Hello world"], depth: 0)
        #expect(out == [.paragraph(raw: "Hello world")])
    }

    @Test("blank line separates two paragraphs")
    func paragraphsSeparatedByBlankLine() {
        let out = BlockParser(defs: DefinitionStore()).parse(["first", "", "second"], depth: 0)
        #expect(out == [.paragraph(raw: "first"), .paragraph(raw: "second")])
    }

    @Test("consecutive lines join into one paragraph with \\n")
    func consecutiveLinesJoinIntoOneParagraph() {
        let out = BlockParser(defs: DefinitionStore()).parse(["line one", "line two"], depth: 0)
        #expect(out == [.paragraph(raw: "line one\nline two")])
    }

    @Test("leading/trailing whitespace per line is trimmed (M10)")
    func perLineWhitespaceTrimmed() {
        let out = BlockParser(defs: DefinitionStore()).parse(["  a  ", "  b  "], depth: 0)
        #expect(out == [.paragraph(raw: "a\nb")])
    }

    @Test("whitespace-only line is treated as blank and separates paragraphs")
    func blankOnlyLinesSeparate() {
        let out = BlockParser(defs: DefinitionStore()).parse(["x", "   ", "y"], depth: 0)
        #expect(out == [.paragraph(raw: "x"), .paragraph(raw: "y")])
    }

    @Test("a non-breaking space is content, not a blank-line separator")
    func nonBreakingSpaceIsNotBlank() {
        // CommonMark: a blank line contains only ASCII space (U+0020) or tab.
        // A line of only NBSP (U+00A0) is ordinary text and must NOT split the
        // paragraph, nor be trimmed away.
        let out = BlockParser(defs: DefinitionStore()).parse(["a", "\u{00A0}", "b"], depth: 0)
        #expect(out == [.paragraph(raw: "a\n\u{00A0}\nb")])
    }

    @Test("empty input produces no blocks")
    func emptyInput() {
        let out = BlockParser(defs: DefinitionStore()).parse([], depth: 0)
        #expect(out == [])
    }
}
