import Testing
@testable import MarkdownAST

@Suite("Hard and soft line breaks")
struct BreakTests {
    private func inlines(_ s: String) -> [MarkdownInline] {
        InlineParser(defs: DefinitionStore()).parse(s, depth: 0)
    }

    @Test("a newline in a paragraph is a soft break")
    func softBreak() {
        #expect(inlines("a\nb") == [.text("a"), .softBreak, .text("b")])
    }

    @Test("two trailing spaces before a newline is a hard break")
    func hardBreakTwoSpaces() {
        #expect(inlines("a  \nb") == [.text("a"), .hardBreak, .text("b")])
    }

    @Test("a backslash before a newline is a hard break")
    func hardBreakBackslash() {
        #expect(inlines("a\\\nb") == [.text("a"), .hardBreak, .text("b")])
    }

    @Test("an escaped backslash before a newline is a soft break")
    func escapedBackslashThenSoftBreak() {
        #expect(inlines("a\\\\\nb") == [.text("a\\"), .softBreak, .text("b")])
    }

    @Test("trailing spaces at the very end are stripped")
    func trailingSpacesStripped() {
        #expect(inlines("a  ") == [.text("a")])
    }
}
