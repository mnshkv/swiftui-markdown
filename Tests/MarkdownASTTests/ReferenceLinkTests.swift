import Testing
@testable import MarkdownAST

@Suite("Reference links and images")
struct ReferenceLinkTests {
    private func inlines(_ s: String, links: [(String, String)] = [("r", "/u")]) -> [MarkdownInline] {
        let store = DefinitionStore()
        for (label, dest) in links { store.addLink(label: label, destination: dest, title: nil) }
        return InlineParser(defs: store).parse(s, depth: 0)
    }

    @Test("full reference link")
    func fullReference() {
        #expect(inlines("[Swift][r]") == [.link(destination: "/u", title: nil, content: [.text("Swift")])])
    }

    @Test("collapsed reference link uses the text as the label")
    func collapsedReference() {
        #expect(inlines("[r][]") == [.link(destination: "/u", title: nil, content: [.text("r")])])
    }

    @Test("shortcut reference link")
    func shortcutReference() {
        #expect(inlines("[r]") == [.link(destination: "/u", title: nil, content: [.text("r")])])
    }

    @Test("unresolved reference is literal text")
    func unresolvedIsLiteral() {
        #expect(inlines("[missing]") == [.text("[missing]")])
    }

    @Test("reference image")
    func referenceImage() {
        #expect(inlines("![alt][r]") == [.image(source: "/u", title: nil, alt: "alt")])
    }

    @Test("escaped bracket in link text is not a terminator")
    func escapedBracketInText() {
        #expect(inlines("[a\\]b][r]") == [.link(destination: "/u", title: nil, content: [.text("a]b")])])
    }

    @Test("code span in link text is opaque to bracket matching")
    func codeSpanInText() {
        #expect(inlines("[a`b]c`][r]") == [
            .link(destination: "/u", title: nil, content: [.text("a"), .code("b]c")])
        ])
    }
}
