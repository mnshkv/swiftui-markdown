import Testing
@testable import MarkdownAST

@Suite("Intraword underscore emphasis (K7, end-to-end)")
struct UnderscoreTests {
    private func inlines(_ s: String) -> [MarkdownInline] {
        InlineParser(defs: DefinitionStore()).parse(s, depth: 0)
    }

    @Test("intraword `a_b_c` is plain text")
    func intrawordNoEmphasis() {
        #expect(inlines("a_b_c") == [.text("a_b_c")])
    }

    @Test("`_a_` is emphasis")
    func underscoreEmphasis() {
        #expect(inlines("_a_") == [.emphasis([.text("a")])])
    }

    @Test("trailing `a_b_` does not emphasize")
    func trailingUnderscoreNoEmphasis() {
        #expect(inlines("a_b_") == [.text("a_b_")])
    }

    @Test("`_a_b_` emphasizes across an intraword underscore")
    func emphasisAcrossIntraword() {
        #expect(inlines("_a_b_") == [.emphasis([.text("a_b")])])
    }

    @Test("`foo_bar_baz` is plain text")
    func longIntrawordNoEmphasis() {
        #expect(inlines("foo_bar_baz") == [.text("foo_bar_baz")])
    }
}
