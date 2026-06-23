import Testing
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("TextDocument model")
struct ModelTests {
    @Test("a document is value-equatable")
    func equatable() {
        let style = TextStyle(fontSize: 17, isBold: false, isItalic: false,
                              isStrikethrough: false, color: .black)
        let p = Paragraph(runs: [.text("hi", style)], style: .body)
        let a = TextDocument(blocks: [.paragraph(p)])
        let b = TextDocument(blocks: [.paragraph(p)])
        #expect(a == b)
    }
}
