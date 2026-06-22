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

    @Test("nested list inside an item (indented marker)")
    func nestedList() {
        let out = BlockParser(defs: DefinitionStore()).parse(["- a", "  - b"], depth: 0)
        #expect(out == [
            .list(RawList(kind: .bullet, isTight: true, items: [
                RawListItem(blocks: [
                    .paragraph(raw: "a"),
                    .list(RawList(kind: .bullet, isTight: true, items: [
                        RawListItem(blocks: [.paragraph(raw: "b")], task: nil),
                    ])),
                ], task: nil),
            ])),
        ])
    }

    @Test("non-indented block start after an item is a sibling, not nested")
    func blockStartEndsItem() {
        let out = BlockParser(defs: DefinitionStore()).parse(["- a", "# H"], depth: 0)
        #expect(out == [
            .list(RawList(kind: .bullet, isTight: true, items: [
                RawListItem(blocks: [.paragraph(raw: "a")], task: nil),
            ])),
            .heading(level: 1, raw: "H"),
        ])
    }

    @Test("non-indented plain line is a lazy continuation of the item")
    func lazyContinuation() {
        let out = BlockParser(defs: DefinitionStore()).parse(["- a", "lazy"], depth: 0)
        #expect(out == [
            .list(RawList(kind: .bullet, isTight: true, items: [
                RawListItem(blocks: [.paragraph(raw: "a\nlazy")], task: nil),
            ])),
        ])
    }

    @Test("blank line between items makes the list loose")
    func looseListWhenBlankBetweenItems() {
        let out = BlockParser(defs: DefinitionStore()).parse(["- a", "", "- b"], depth: 0)
        #expect(out == [
            .list(RawList(kind: .bullet, isTight: false, items: [
                RawListItem(blocks: [.paragraph(raw: "a")], task: nil),
                RawListItem(blocks: [.paragraph(raw: "b")], task: nil),
            ])),
        ])
    }

    @Test("no blank lines makes the list tight")
    func tightListNoBlanks() {
        let out = BlockParser(defs: DefinitionStore()).parse(["- a", "- b"], depth: 0)
        #expect(out == [
            .list(RawList(kind: .bullet, isTight: true, items: [
                RawListItem(blocks: [.paragraph(raw: "a")], task: nil),
                RawListItem(blocks: [.paragraph(raw: "b")], task: nil),
            ])),
        ])
    }

    @Test("blank line inside an item makes the list loose (multi-paragraph item)")
    func looseWhenBlankInsideItem() {
        let out = BlockParser(defs: DefinitionStore()).parse(["- a", "", "  b"], depth: 0)
        #expect(out == [
            .list(RawList(kind: .bullet, isTight: false, items: [
                RawListItem(blocks: [.paragraph(raw: "a"), .paragraph(raw: "b")], task: nil),
            ])),
        ])
    }

    @Test("trailing blank after the last item is ignored (stays tight)")
    func tightWithTrailingBlank() {
        let out = BlockParser(defs: DefinitionStore()).parse(["- a", "- b", ""], depth: 0)
        #expect(out == [
            .list(RawList(kind: .bullet, isTight: true, items: [
                RawListItem(blocks: [.paragraph(raw: "a")], task: nil),
                RawListItem(blocks: [.paragraph(raw: "b")], task: nil),
            ])),
        ])
    }
}
