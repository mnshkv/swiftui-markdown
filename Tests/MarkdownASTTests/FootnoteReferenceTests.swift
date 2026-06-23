import Testing
@testable import MarkdownAST

@Suite("Inline footnote references and bodies")
struct FootnoteReferenceTests {
    @Test("footnote reference resolves when a definition exists")
    func footnoteReferenceResolves() {
        let doc = MarkdownParser.parse("Text[^1]\n\n[^1]: note")
        #expect(doc.blocks == [.paragraph(content: [.text("Text"), .footnoteReference(id: "1")])])
        #expect(doc.footnotes == [
            FootnoteDefinition(id: "1", blocks: [.paragraph(content: [.text("note")])])
        ])
    }

    @Test("a reference with no definition is literal text")
    func unknownFootnoteReferenceIsLiteral() {
        let doc = MarkdownParser.parse("Text[^x]")
        #expect(doc.blocks == [.paragraph(content: [.text("Text[^x]")])])
    }

    @Test("a multi-paragraph footnote body renders multiple blocks")
    func multiParagraphFootnoteBody() {
        let doc = MarkdownParser.parse("Use[^1]\n\n[^1]: para one\n\n    para two")
        #expect(doc.footnotes.count == 1)
        #expect(doc.footnotes.first?.blocks.count == 2)
    }
}
