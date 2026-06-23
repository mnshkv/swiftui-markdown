import Testing
@testable import MarkdownAST

@Suite("Emphasis / strong (process_emphasis)")
struct EmphasisTests {
    private func inlines(_ s: String) -> [MarkdownInline] {
        InlineParser(defs: DefinitionStore()).parse(s, depth: 0)
    }

    @Test("`*hi*` is emphasis")
    func starEmphasis() {
        #expect(inlines("*hi*") == [.emphasis([.text("hi")])])
    }

    @Test("`_hi_` is emphasis")
    func underscoreEmphasis() {
        #expect(inlines("_hi_") == [.emphasis([.text("hi")])])
    }

    @Test("`**hi**` is strong")
    func doubleStarStrong() {
        #expect(inlines("**hi**") == [.strong([.text("hi")])])
    }

    @Test("strong nested in emphasis: `*a **b** c*`")
    func strongInsideEmphasis() {
        #expect(inlines("*a **b** c*") == [
            .emphasis([.text("a "), .strong([.text("b")]), .text(" c")])
        ])
    }

    @Test("intraword underscore is not emphasis: `a_b_c`")
    func intrawordUnderscoreNotEmphasis() {
        #expect(inlines("a_b_c") == [.text("a_b_c")])
    }

    @Test("unmatched star is literal: `a * b`")
    func unmatchedStarIsLiteral() {
        #expect(inlines("a * b") == [.text("a * b")])
    }

    @Test("`***a***` is emphasis wrapping strong (CM 413)")
    func tripleStarEmStrong() {
        #expect(inlines("***a***") == [.emphasis([.strong([.text("a")])])])
    }

    @Test("emphasis containing strong runs: `*a**b**c*`")
    func emphasisWithInnerStrong() {
        #expect(inlines("*a**b**c*") == [
            .emphasis([.text("a"), .strong([.text("b")]), .text("c")])
        ])
    }
}
