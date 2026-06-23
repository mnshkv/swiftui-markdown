import Testing
@testable import MarkdownAST

@Suite("CommonMark autolinks")
struct AutolinkTests {
    private func inlines(_ s: String) -> [MarkdownInline] {
        InlineParser(defs: DefinitionStore()).parse(s, depth: 0)
    }

    @Test("URI autolink")
    func uriAutolink() {
        #expect(inlines("<https://swift.org>") == [.autolink(url: "https://swift.org")])
    }

    @Test("email autolink stores the raw address")
    func emailAutolink() {
        #expect(inlines("<a@b.com>") == [.autolink(url: "a@b.com")])
    }

    @Test("empty scheme content is literal text")
    func emptyMailtoLiteral() {
        #expect(inlines("<mailto:>") == [.text("<mailto:>")])
    }

    @Test("no scheme is literal text")
    func noSchemeLiteral() {
        #expect(inlines("<no scheme>") == [.text("<no scheme>")])
    }

    @Test("autolink between text coalesces neighbors")
    func autolinkInContext() {
        #expect(inlines("see <https://x.org> now") == [
            .text("see "),
            .autolink(url: "https://x.org"),
            .text(" now")
        ])
    }
}
