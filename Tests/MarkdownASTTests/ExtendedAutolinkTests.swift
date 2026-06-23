import Testing
@testable import MarkdownAST

@Suite("GFM extended (bare) autolinks")
struct ExtendedAutolinkTests {
    private func inlines(_ s: String) -> [MarkdownInline] {
        InlineParser(defs: DefinitionStore()).parse(s, depth: 0)
    }

    @Test("bare https URL between text")
    func bareURL() {
        #expect(inlines("see https://swift.org now") == [
            .text("see "), .autolink(url: "https://swift.org"), .text(" now")
        ])
    }

    @Test("www. URL with a trailing sentence dot")
    func wwwTrailingDot() {
        #expect(inlines("at www.swift.org.") == [
            .text("at "), .autolink(url: "www.swift.org"), .text(".")
        ])
    }

    @Test("trailing unmatched paren is not part of the URL")
    func balancedParen() {
        #expect(inlines("(https://a.com)") == [
            .text("("), .autolink(url: "https://a.com"), .text(")")
        ])
    }

    @Test("trailing dot is trimmed")
    func trailingDot() {
        #expect(inlines("https://a.com.") == [.autolink(url: "https://a.com"), .text(".")])
    }

    @Test("trailing bang is trimmed")
    func trailingBang() {
        #expect(inlines("https://a.com!") == [.autolink(url: "https://a.com"), .text("!")])
    }

    @Test("bare email")
    func bareEmail() {
        #expect(inlines("contact a@b.com now") == [
            .text("contact "), .autolink(url: "a@b.com"), .text(" now")
        ])
    }
}
