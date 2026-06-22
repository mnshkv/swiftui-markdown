import Testing
@testable import MarkdownAST

@Suite("Smoke")
struct SmokeTests {
    @Test("parse(empty) returns empty document")
    func parseEmpty() {
        #expect(MarkdownParser.parse("") == MarkdownDocument(blocks: [], footnotes: []))
    }

    @Test("parse never returns nil-equivalent — always a document")
    func parseAnyReturnsDocument() {
        let doc = MarkdownParser.parse("# Some heading\n\nParagraph.")
        #expect(doc.blocks == [])
        #expect(doc.footnotes == [])
    }
}