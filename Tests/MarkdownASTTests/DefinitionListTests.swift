import Testing
@testable import MarkdownAST

@Suite("Definition lists (Pass A raw leaves)")
struct DefinitionListTests {
    @Test("single detail under a one-line term")
    func singleDetail() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["Term", ": Definition"],
            depth: 0
        )
        #expect(out == [
            .definitionList([
                RawDefinition(term: "Term", details: [[.paragraph(raw: "Definition")]])
            ])
        ])
    }

    @Test("two colon lines are two separate details")
    func twoDetails() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["A", ": one", ": two"],
            depth: 0
        )
        #expect(out == [
            .definitionList([
                RawDefinition(term: "A", details: [
                    [.paragraph(raw: "one")],
                    [.paragraph(raw: "two")]
                ])
            ])
        ])
    }

    @Test("indented continuation line folds into the current detail")
    func multilineDetail() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["Term", ": line1", "  line2"],
            depth: 0
        )
        #expect(out == [
            .definitionList([
                RawDefinition(term: "Term", details: [
                    [.paragraph(raw: "line1\nline2")]
                ])
            ])
        ])
    }

    @Test("two term/detail pairs merge into one definition list")
    func twoDefinitionsMerged() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["A", ": one", "B", ": two"],
            depth: 0
        )
        #expect(out == [
            .definitionList([
                RawDefinition(term: "A", details: [[.paragraph(raw: "one")]]),
                RawDefinition(term: "B", details: [[.paragraph(raw: "two")]])
            ])
        ])
    }

    @Test("colon line without a one-line term is paragraph text")
    func colonWithoutTermIsParagraph() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            [": no term"],
            depth: 0
        )
        #expect(out == [.paragraph(raw: ": no term")])
    }

    @Test("two-line term is not a definition list")
    func twoLineTermNotDefList() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["line1", "line2", ": def"],
            depth: 0
        )
        #expect(out == [.paragraph(raw: "line1\nline2\n: def")])
    }

    @Test("definition list followed by a sibling paragraph")
    func defListFollowedBySibling() {
        let out = BlockParser(defs: DefinitionStore()).parse(
            ["Term", ": def", "after"],
            depth: 0
        )
        #expect(out == [
            .definitionList([
                RawDefinition(term: "Term", details: [[.paragraph(raw: "def")]])
            ]),
            .paragraph(raw: "after")
        ])
    }
}
