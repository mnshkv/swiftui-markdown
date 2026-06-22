import Testing
@testable import MarkdownAST

@Suite("Lists (Pass A raw leaves)")
struct ListTests {
    @Test("flat bullet list with two items")
    func bulletList() {
        let out = BlockParser(defs: DefinitionStore()).parse(["- a", "- b"], depth: 0)
        #expect(out == [
            .list(RawList(kind: .bullet, isTight: true, items: [
                RawListItem(blocks: [.paragraph(raw: "a")], task: nil),
                RawListItem(blocks: [.paragraph(raw: "b")], task: nil),
            ]))
        ])
    }

    @Test("ordered list keeps its start number")
    func orderedListStart() {
        let out = BlockParser(defs: DefinitionStore()).parse(["3. x", "4. y"], depth: 0)
        #expect(out == [
            .list(RawList(kind: .ordered(start: 3), isTight: true, items: [
                RawListItem(blocks: [.paragraph(raw: "x")], task: nil),
                RawListItem(blocks: [.paragraph(raw: "y")], task: nil),
            ]))
        ])
    }
}
