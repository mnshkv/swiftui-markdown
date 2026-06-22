import Testing
@testable import MarkdownAST

@Suite("Model")
struct ModelTests {
    @Test("heading block constructs and equates")
    func headingBlock() {
        let a: MarkdownBlock = .heading(level: 2, content: [.text("Hi")])
        let b: MarkdownBlock = .heading(level: 2, content: [.text("Hi")])
        #expect(a == b)
        #expect(a != .heading(level: 3, content: [.text("Hi")]))
    }

    @Test("list with task items constructs and equates")
    func listWithTasks() {
        let itemA = MarkdownListItem(blocks: [.paragraph(content: [.text("todo")])], task: .unchecked)
        let itemB = MarkdownListItem(blocks: [.paragraph(content: [.text("done")])], task: .checked)
        let list = MarkdownList(kind: .bullet, isTight: true, items: [itemA, itemB])
        #expect(list.kind == .bullet)
        #expect(list.isTight == true)
        #expect(list.items.count == 2)
        #expect(list.items[0].task == .unchecked)
        #expect(list.items[1].task == .checked)
        let same = MarkdownList(kind: .bullet, isTight: true, items: [itemA, itemB])
        #expect(list == same)
    }

    @Test("ordered list kind carries start")
    func orderedKind() {
        #expect(MarkdownList.Kind.ordered(start: 3) == .ordered(start: 3))
        #expect(MarkdownList.Kind.ordered(start: 3) != .ordered(start: 1))
        #expect(MarkdownList.Kind.bullet != .ordered(start: 1))
    }

    @Test("table constructs and equates")
    func table() {
        let header: [[MarkdownInline]] = [[.text("A")], [.text("B")]]
        let rows: [[[MarkdownInline]]] = [[ [.text("1")], [.text("2")] ]]
        let t = MarkdownTable(alignments: [.left, .right], header: header, rows: rows)
        #expect(t.alignments == [.left, .right])
        #expect(t.rows.count == 1)
        let same = MarkdownTable(alignments: [.left, .right], header: header, rows: rows)
        #expect(t == same)
    }

    @Test("definition list constructs and equates")
    func definition() {
        let d = MarkdownDefinition(
            term: [.text("term")],
            details: [[.paragraph(content: [.text("detail")])]]
        )
        #expect(d.term == [.text("term")])
        #expect(d.details.count == 1)
        let same = MarkdownDefinition(
            term: [.text("term")],
            details: [[.paragraph(content: [.text("detail")])]]
        )
        #expect(d == same)
    }

    @Test("footnote definition constructs and equates")
    func footnote() {
        let f = FootnoteDefinition(id: "1", blocks: [.paragraph(content: [.text("note")])])
        #expect(f.id == "1")
        #expect(f.blocks.count == 1)
        let same = FootnoteDefinition(id: "1", blocks: [.paragraph(content: [.text("note")])])
        #expect(f == same)
    }

    @Test("inline emphasis/strike/code equate")
    func inlines() {
        #expect(MarkdownInline.emphasis([.text("x")]) == .emphasis([.text("x")]))
        #expect(MarkdownInline.strikethrough([.text("x")]) == .strikethrough([.text("x")]))
        #expect(MarkdownInline.code("let x = 1") == .code("let x = 1"))
        #expect(MarkdownInline.softBreak == .softBreak)
        #expect(MarkdownInline.hardBreak == .hardBreak)
        #expect(MarkdownInline.softBreak != .hardBreak)
    }

    @Test("link/image/autolink/footnoteRef equate")
    func linkLike() {
        #expect(MarkdownInline.link(destination: "u", title: nil, content: [.text("c")])
                == .link(destination: "u", title: nil, content: [.text("c")]))
        #expect(MarkdownInline.image(source: "s", title: "t", alt: "alt")
                == .image(source: "s", title: "t", alt: "alt"))
        #expect(MarkdownInline.autolink(url: "https://example.com") == .autolink(url: "https://example.com"))
        #expect(MarkdownInline.footnoteReference(id: "a") == .footnoteReference(id: "a"))
    }

    @Test("block quote nests blocks")
    func blockQuote() {
        let bq: MarkdownBlock = .blockQuote(blocks: [.paragraph(content: [.text("q")])])
        let same: MarkdownBlock = .blockQuote(blocks: [.paragraph(content: [.text("q")])])
        #expect(bq == same)
    }

    @Test("code block and thematic break")
    func codeAndBreak() {
        #expect(MarkdownBlock.codeBlock(language: "swift", code: "let x = 1")
                == .codeBlock(language: "swift", code: "let x = 1"))
        #expect(MarkdownBlock.codeBlock(language: nil, code: "x") != .codeBlock(language: "swift", code: "x"))
        #expect(MarkdownBlock.thematicBreak == .thematicBreak)
    }

    @Test("document equates with footnotes")
    func document() {
        let doc = MarkdownDocument(
            blocks: [.thematicBreak],
            footnotes: [FootnoteDefinition(id: "1", blocks: [.paragraph(content: [.text("n")])])]
        )
        let same = MarkdownDocument(
            blocks: [.thematicBreak],
            footnotes: [FootnoteDefinition(id: "1", blocks: [.paragraph(content: [.text("n")])])]
        )
        #expect(doc == same)
    }
}