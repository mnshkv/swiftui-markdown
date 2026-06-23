import Testing
@testable import MarkdownAST

@Suite("Inline links and images")
struct LinkTests {
    private func inlines(_ s: String) -> [MarkdownInline] {
        InlineParser(defs: DefinitionStore()).parse(s, depth: 0)
    }

    @Test("inline link")
    func inlineLink() {
        #expect(inlines("[a](http://x)") == [
            .link(destination: "http://x", title: nil, content: [.text("a")])
        ])
    }

    @Test("inline link with title")
    func inlineLinkWithTitle() {
        #expect(inlines("[a](http://x \"T\")") == [
            .link(destination: "http://x", title: "T", content: [.text("a")])
        ])
    }

    @Test("inline image with alt text")
    func inlineImage() {
        #expect(inlines("![alt](http://x)") == [
            .image(source: "http://x", title: nil, alt: "alt")
        ])
    }

    @Test("image alt reduces inner markup to plain text")
    func imageAltReduction() {
        #expect(inlines("![*alt*](http://x)") == [
            .image(source: "http://x", title: nil, alt: "alt")
        ])
    }

    @Test("emphasis inside link text is resolved")
    func emphasisInsideLinkText() {
        #expect(inlines("[*hi*](http://x)") == [
            .link(destination: "http://x", title: nil, content: [.emphasis([.text("hi")])])
        ])
    }

    @Test("link surrounded by text coalesces neighbors")
    func linkInContext() {
        #expect(inlines("see [a](http://x) now") == [
            .text("see "),
            .link(destination: "http://x", title: nil, content: [.text("a")]),
            .text(" now")
        ])
    }
}
