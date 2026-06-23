import Testing
@testable import MarkdownAST

@Suite("Image alt reduction & link tokenizer wiring (T37/T38)")
struct ImageTests {
    private func inlines(_ s: String) -> [MarkdownInline] {
        InlineParser(defs: DefinitionStore()).parse(s, depth: 0)
    }

    @Test("emphasis in alt reduces to plain text")
    func emphasisAltReduced() {
        #expect(inlines("![*alt*](x)") == [.image(source: "x", title: nil, alt: "alt")])
    }

    @Test("multi-word alt is preserved")
    func multiWordAlt() {
        #expect(inlines("![a b](x)") == [.image(source: "x", title: nil, alt: "a b")])
    }

    @Test("a link followed by trailing text coalesces")
    func linkThenTextCoalesces() {
        #expect(inlines("[a](x)!") == [
            .link(destination: "x", title: nil, content: [.text("a")]),
            .text("!")
        ])
    }

    @Test("two adjacent links keep their boundary")
    func twoAdjacentLinks() {
        #expect(inlines("[a](x)[b](y)") == [
            .link(destination: "x", title: nil, content: [.text("a")]),
            .link(destination: "y", title: nil, content: [.text("b")])
        ])
    }
}
