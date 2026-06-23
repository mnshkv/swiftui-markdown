import Testing
@testable import MarkdownAST

@Suite("GFM strikethrough")
struct StrikethroughTests {
    private func inlines(_ s: String) -> [MarkdownInline] {
        InlineParser(defs: DefinitionStore()).parse(s, depth: 0)
    }

    @Test("`~~gone~~` is strikethrough")
    func strikethrough() {
        #expect(inlines("~~gone~~") == [.strikethrough([.text("gone")])])
    }

    @Test("a single `~` is literal text")
    func singleTildeLiteral() {
        #expect(inlines("a ~ b") == [.text("a ~ b")])
    }

    @Test("a length-3 `~~~` run does not strike (v1: longer runs literal)")
    func tripleTildeLiteral() {
        #expect(inlines("~~~nope~~~") == [.text("~~~nope~~~")])
    }

    @Test("strikethrough wraps inner emphasis")
    func strikethroughWithEmphasis() {
        #expect(inlines("~~a *b* c~~") == [
            .strikethrough([.text("a "), .emphasis([.text("b")]), .text(" c")]),
        ])
    }
}
