import Testing
@testable import MarkdownAST

@Suite("Pass B — deferred inline resolution")
struct PassBTests {
    @Test("paragraph and heading text are resolved into inline nodes")
    func leavesResolved() {
        let doc = MarkdownParser.parse("# Some heading\n\nParagraph.")
        #expect(doc.blocks == [
            .heading(level: 1, content: [.text("Some heading")]),
            .paragraph(content: [.text("Paragraph.")])
        ])
    }

    @Test("forward link reference resolves (def after use)")
    func forwardLinkReference() {
        let doc = MarkdownParser.parse("[Swift][sw]\n\n[sw]: https://swift.org")
        #expect(doc.blocks == [
            .paragraph(content: [
                .link(destination: "https://swift.org", title: nil, content: [.text("Swift")])
            ])
        ])
    }

    @Test("backward link reference resolves (def before use)")
    func backwardLinkReference() {
        let doc = MarkdownParser.parse("[sw]: https://swift.org\n\n[Swift][sw]")
        #expect(doc.blocks == [
            .paragraph(content: [
                .link(destination: "https://swift.org", title: nil, content: [.text("Swift")])
            ])
        ])
    }

    @Test("forward footnote reference resolves and footnote body is parsed")
    func forwardFootnote() {
        let doc = MarkdownParser.parse("Text[^1]\n\n[^1]: note")
        #expect(doc.blocks == [
            .paragraph(content: [.text("Text"), .footnoteReference(id: "1")])
        ])
        #expect(doc.footnotes == [
            FootnoteDefinition(id: "1", blocks: [.paragraph(content: [.text("note")])])
        ])
    }

    @Test("blockquote paragraphs are inline-parsed after Pass A completes")
    func blockquoteInlineResolved() {
        let doc = MarkdownParser.parse("> hello")
        #expect(doc.blocks == [.blockQuote(blocks: [.paragraph(content: [.text("hello")])])])
    }
}
