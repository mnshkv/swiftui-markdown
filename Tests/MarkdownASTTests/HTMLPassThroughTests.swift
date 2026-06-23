import Testing
@testable import MarkdownAST

@Suite("HTML and entity pass-through (documented limitations)")
struct HTMLPassThroughTests {
    @Test("a raw HTML block flows through as literal text")
    func rawHTMLBlockLiteral() {
        let doc = MarkdownParser.parse("<div>x</div>")
        #expect(doc.blocks == [.paragraph(content: [.text("<div>x</div>")])])
    }

    @Test("inline raw HTML is literal text")
    func inlineHTMLLiteral() {
        let doc = MarkdownParser.parse("a <b>c</b> d")
        #expect(doc.blocks == [.paragraph(content: [.text("a <b>c</b> d")])])
    }

    @Test("an entity reference is literal text (not decoded)")
    func entityLiteral() {
        let doc = MarkdownParser.parse("AT&amp;T")
        #expect(doc.blocks == [.paragraph(content: [.text("AT&amp;T")])])
    }
}
