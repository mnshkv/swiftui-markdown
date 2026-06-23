import Testing
import CoreGraphics
@testable import Marked

@Suite("BlockMapper — special features")
struct SpecialFeaturesTests {

    let ctx = StyleContext(.default, .light)
    var map: ([MarkdownBlock]) -> [Block] {
        { BlockMapper.map($0, ctx: ctx, footnotes: [:]) }
    }

    // MARK: - Task 4.1: task checkboxes

    @Test("checked task item → first paragraph's first run is '☑ '")
    func checkedTaskItem() {
        let item = MarkdownListItem(
            blocks: [.paragraph(content: [.text("do")])],
            task: .checked
        )
        let mdList = MarkdownList(kind: .bullet, isTight: true, items: [item])
        let blocks = map([.list(mdList)])
        guard case .list(let list) = blocks.first else {
            Issue.record("Expected .list"); return
        }
        guard let firstItem = list.items.first else {
            Issue.record("Expected item"); return
        }
        guard case .paragraph(let p) = firstItem.blocks.first else {
            Issue.record("Expected .paragraph in item"); return
        }
        guard case .text(let s, _) = p.runs.first else {
            Issue.record("Expected .text run as first run"); return
        }
        #expect(s == "☑ ")
        guard case .text(let s2, _) = p.runs.dropFirst().first else {
            Issue.record("Expected second .text run"); return
        }
        #expect(s2 == "do")
    }

    @Test("unchecked task item → first paragraph's first run is '☐ '")
    func uncheckedTaskItem() {
        let item = MarkdownListItem(
            blocks: [.paragraph(content: [.text("todo")])],
            task: .unchecked
        )
        let mdList = MarkdownList(kind: .bullet, isTight: true, items: [item])
        let blocks = map([.list(mdList)])
        guard case .list(let list) = blocks.first else {
            Issue.record("Expected .list"); return
        }
        guard let firstItem = list.items.first else {
            Issue.record("Expected item"); return
        }
        guard case .paragraph(let p) = firstItem.blocks.first else {
            Issue.record("Expected .paragraph in item"); return
        }
        guard case .text(let s, _) = p.runs.first else {
            Issue.record("Expected .text run as first run"); return
        }
        #expect(s == "☐ ")
    }

    @Test("non-task item → no checkbox prefix")
    func nonTaskItem() {
        let item = MarkdownListItem(
            blocks: [.paragraph(content: [.text("plain")])],
            task: nil
        )
        let mdList = MarkdownList(kind: .bullet, isTight: true, items: [item])
        let blocks = map([.list(mdList)])
        guard case .list(let list) = blocks.first else {
            Issue.record("Expected .list"); return
        }
        guard let firstItem = list.items.first else {
            Issue.record("Expected item"); return
        }
        guard case .paragraph(let p) = firstItem.blocks.first else {
            Issue.record("Expected .paragraph in item"); return
        }
        guard case .text(let s, _) = p.runs.first else {
            Issue.record("Expected .text run"); return
        }
        #expect(s == "plain")
    }

    // MARK: - Task 4.1: definition list

    @Test("definitionList → bold term paragraph + indented detail paragraph")
    func definitionList() {
        let def = MarkdownDefinition(
            term: [.text("T")],
            details: [[.paragraph(content: [.text("d")])]]
        )
        let blocks = map([.definitionList([def])])
        #expect(blocks.count == 2)

        // First block: bold term paragraph
        guard case .paragraph(let termPara) = blocks.first else {
            Issue.record("Expected term .paragraph as first block"); return
        }
        guard case .text(let termStr, let termStyle) = termPara.runs.first else {
            Issue.record("Expected .text run in term paragraph"); return
        }
        #expect(termStr == "T")
        #expect(termStyle.isBold)

        // Second block: indented detail paragraph
        guard case .paragraph(let detailPara) = blocks.last else {
            Issue.record("Expected detail .paragraph as second block"); return
        }
        let indent = StyleContext(.default, .light).style.spacing.definitionIndent
        #expect(detailPara.style.leadingIndent == indent)
        guard case .text(let detailStr, _) = detailPara.runs.first else {
            Issue.record("Expected .text run in detail paragraph"); return
        }
        #expect(detailStr == "d")
    }

    @Test("definitionList with multiple defs → term+detail pairs in order")
    func definitionListMultipleDefs() {
        let def1 = MarkdownDefinition(
            term: [.text("A")],
            details: [[.paragraph(content: [.text("a detail")])]]
        )
        let def2 = MarkdownDefinition(
            term: [.text("B")],
            details: [[.paragraph(content: [.text("b detail")])]]
        )
        let blocks = map([.definitionList([def1, def2])])
        // 2 defs × (1 term + 1 detail) = 4 blocks
        #expect(blocks.count == 4)
    }

    @Test("definitionList with multiple details → all indented")
    func definitionListMultipleDetails() {
        let def = MarkdownDefinition(
            term: [.text("T")],
            details: [
                [.paragraph(content: [.text("d1")])],
                [.paragraph(content: [.text("d2")])]
            ]
        )
        let blocks = map([.definitionList([def])])
        // 1 term + 2 details = 3 blocks
        #expect(blocks.count == 3)
        let indent = StyleContext(.default, .light).style.spacing.definitionIndent
        for block in blocks.dropFirst() {
            guard case .paragraph(let p) = block else {
                Issue.record("Expected .paragraph for detail"); return
            }
            #expect(p.style.leadingIndent == indent)
        }
    }

    // MARK: - Task 4.2: lone-image block promotion

    @Test("paragraph with lone image → block .image")
    func loneImagePromotion() {
        let blocks = map([.paragraph(content: [.image(source: "i", title: nil, alt: "a")])])
        guard case .image(let att) = blocks.first else {
            Issue.record("Expected block .image"); return
        }
        #expect(att.source == "i")
        #expect(att.alt == "a")
        let expectedSize = StyleContext(.default, .light).style.blockImage
        #expect(att.intrinsicSize == expectedSize)
    }

    @Test("paragraph with image + non-whitespace text → stays .paragraph (inline image)")
    func mixedParagraphStaysInline() {
        let blocks = map([.paragraph(content: [.text("see "), .image(source: "i", title: nil, alt: "a")])])
        guard case .paragraph(_) = blocks.first else {
            Issue.record("Expected .paragraph (not promoted)"); return
        }
    }

    @Test("paragraph with whitespace around image → promoted to block .image")
    func whitespaceAroundImagePromoted() {
        let blocks = map([.paragraph(content: [
            .text("  "),
            .image(source: "img", title: nil, alt: "alt"),
            .text(" ")
        ])])
        guard case .image(let att) = blocks.first else {
            Issue.record("Expected block .image"); return
        }
        #expect(att.source == "img")
        #expect(att.alt == "alt")
    }

    @Test("paragraph with softBreak around image → promoted to block .image")
    func softBreakAroundImagePromoted() {
        let blocks = map([.paragraph(content: [
            .softBreak,
            .image(source: "s", title: nil, alt: "b"),
            .softBreak
        ])])
        guard case .image(let att) = blocks.first else {
            Issue.record("Expected block .image"); return
        }
        #expect(att.source == "s")
    }
}
