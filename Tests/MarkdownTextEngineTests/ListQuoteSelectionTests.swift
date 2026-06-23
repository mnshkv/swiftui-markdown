import Testing
import CoreGraphics
import CoreText
@testable import MarkdownTextEngine

// MARK: - Helpers

private func textStyle() -> TextStyle {
    TextStyle(fontSize: 17, color: CGColor(gray: 0, alpha: 1))
}

private func paraBlock(_ text: String) -> Block {
    .paragraph(Paragraph(runs: [.text(text, textStyle())], style: .body))
}

private func itemDoc(_ text: String) -> TextDocument {
    TextDocument(blocks: [paraBlock(text)])
}

// MARK: - Task 4.4: Selection through lists and quotes

@Suite("Selection through lists and quotes (Task 4.4)")
struct ListQuoteSelectionTests {

    // ------------------------------------------------------------------
    // 4.4-A: flattenedText of a list block joins items with "\n"
    // ------------------------------------------------------------------
    @Test("flattenedText joins list items with newline")
    func flattenedTextList() {
        let list = List(marker: .bullet, isTight: true, items: [
            itemDoc("First"),
            itemDoc("Second")
        ])
        let doc = TextDocument(blocks: [.list(list)])
        let flat = flattenedText(doc)
        // Single block (the list), its text = "First\nSecond"
        #expect(flat == "First\nSecond")
    }

    // ------------------------------------------------------------------
    // 4.4-B: flattenedText of a quote block returns inner text
    // ------------------------------------------------------------------
    @Test("flattenedText of quote returns inner document text")
    func flattenedTextQuote() {
        let innerDoc = TextDocument(blocks: [paraBlock("Quoted")])
        let doc = TextDocument(blocks: [.quote(innerDoc)])
        let flat = flattenedText(doc)
        #expect(flat == "Quoted")
    }

    // ------------------------------------------------------------------
    // 4.4-C: multi-block doc with list: correct UTF-16 bases
    // ------------------------------------------------------------------
    @Test("UTF-16 bases are correct for doc with paragraph then list")
    func utf16BasesForDocWithList() {
        // Doc: ["Intro", list("Alpha", "Beta")]
        // flattenedText = "Intro\nAlpha\nBeta"
        // block 0 (paragraph "Intro"): base=0, len=5
        // separator: 1
        // block 1 (list): base=6, len="Alpha\nBeta".utf16.count = 10
        let list = List(marker: .bullet, isTight: true, items: [
            itemDoc("Alpha"),
            itemDoc("Beta")
        ])
        let doc = TextDocument(blocks: [
            paraBlock("Intro"),
            .list(list)
        ])
        let bases = utf16Bases(for: doc)
        #expect(bases.count == 2)
        #expect(bases[0] == 0)
        #expect(bases[1] == 6)  // "Intro" (5) + "\n" (1) = 6
        let flat = flattenedText(doc)
        #expect(flat == "Intro\nAlpha\nBeta")
    }

    // ------------------------------------------------------------------
    // 4.4-D: selectionRects spanning two list items returns rects in both
    // ------------------------------------------------------------------
    @Test("selectionRects spans two list items — returns rects in both")
    func selectionSpansTwoListItems() {
        let list = List(marker: .bullet, isTight: true, items: [
            itemDoc("First item"),
            itemDoc("Second item")
        ])
        let doc = TextDocument(blocks: [.list(list)])
        let layout = LayoutEngine.layout(doc, width: 400)
        let flat = flattenedText(doc)
        // flat = "First item\nSecond item"
        // Select all of it
        let range = TextRange(
            start: TextPosition(index: 0),
            end: TextPosition(index: flat.utf16.count)
        )
        let rects = selectionRects(for: range, in: layout, doc: doc)
        // Should get at least 2 rects (one per item)
        #expect(rects.count >= 2, "Expected rects in both list items, got \(rects.count)")
        // First rect should be above the second rect (items stack vertically)
        if rects.count >= 2 {
            #expect(rects[0].origin.y <= rects[1].origin.y,
                    "First item rect should be at or above second item rect")
        }
    }

    // ------------------------------------------------------------------
    // 4.4-E: copyText across two list items returns both items' text joined
    // ------------------------------------------------------------------
    @Test("copyText across two list items returns both items text")
    func copyTextAcrossTwoListItems() {
        let list = List(marker: .bullet, isTight: true, items: [
            itemDoc("First item"),
            itemDoc("Second item")
        ])
        let doc = TextDocument(blocks: [.list(list)])
        let flat = flattenedText(doc)
        // flat = "First item\nSecond item"
        let range = TextRange(
            start: TextPosition(index: 0),
            end: TextPosition(index: flat.utf16.count)
        )
        let copied = copyText(for: range, doc: doc)
        #expect(copied == "First item\nSecond item")
    }

    // ------------------------------------------------------------------
    // 4.4-F: selectionRects for selection inside a quote returns rects
    // ------------------------------------------------------------------
    @Test("selectionRects inside a quote returns non-empty rects")
    func selectionInsideQuote() {
        let innerDoc = TextDocument(blocks: [paraBlock("Quoted text")])
        let doc = TextDocument(blocks: [.quote(innerDoc)])
        let layout = LayoutEngine.layout(doc, width: 400)
        let flat = flattenedText(doc)
        // flat = "Quoted text"
        let range = TextRange(
            start: TextPosition(index: 0),
            end: TextPosition(index: flat.utf16.count)
        )
        let rects = selectionRects(for: range, in: layout, doc: doc)
        #expect(!rects.isEmpty, "Should get selection rects inside quote")
        if let first = rects.first {
            #expect(first.origin.x >= quoteIndent,
                    "Quote selection rect x should be at or past quoteIndent")
        }
    }

    // ------------------------------------------------------------------
    // 4.4-G: selection spanning quote and paragraph outside returns rects in both
    // ------------------------------------------------------------------
    @Test("selection spanning quote and following paragraph returns rects in both")
    func selectionSpansQuoteAndParagraph() {
        let innerDoc = TextDocument(blocks: [paraBlock("Quote text")])
        let doc = TextDocument(blocks: [
            .quote(innerDoc),
            paraBlock("Outside text")
        ])
        let layout = LayoutEngine.layout(doc, width: 400)
        let flat = flattenedText(doc)
        // flat = "Quote text\nOutside text"
        #expect(flat == "Quote text\nOutside text")
        let range = TextRange(
            start: TextPosition(index: 0),
            end: TextPosition(index: flat.utf16.count)
        )
        let rects = selectionRects(for: range, in: layout, doc: doc)
        #expect(rects.count >= 2, "Expected rects in both quote and paragraph, got \(rects.count)")
    }

    // ------------------------------------------------------------------
    // 4.4-H: copyText for selection spanning quote then paragraph
    // ------------------------------------------------------------------
    @Test("copyText spanning quote then paragraph returns correct text")
    func copyTextSpansQuoteAndParagraph() {
        let innerDoc = TextDocument(blocks: [paraBlock("Quote text")])
        let doc = TextDocument(blocks: [
            .quote(innerDoc),
            paraBlock("Outside text")
        ])
        let flat = flattenedText(doc)
        let range = TextRange(
            start: TextPosition(index: 0),
            end: TextPosition(index: flat.utf16.count)
        )
        let copied = copyText(for: range, doc: doc)
        #expect(copied == "Quote text\nOutside text")
    }

    // ------------------------------------------------------------------
    // 4.4-I: hit-test inside second list item returns position within that item
    // ------------------------------------------------------------------
    @Test("hit-test inside second list item returns position inside second item")
    func hitTestInSecondListItem() {
        let list = List(marker: .bullet, isTight: true, items: [
            itemDoc("First"),
            itemDoc("Second")
        ])
        let doc = TextDocument(blocks: [.list(list)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .list(_, let itemLayouts, _, _) = layout.blocks[0],
              itemLayouts.count >= 2 else {
            Issue.record("expected list with 2 items"); return
        }

        // Find second item's first text block to get its y position
        let secondItemLayout = itemLayouts[1]
        guard case .text(let rect, _) = secondItemLayout.blocks[0] else {
            Issue.record("second item block[0] not text"); return
        }

        // Hit-test in the middle of the second item
        let hitPoint = CGPoint(x: rect.origin.x + 5, y: rect.midY)
        let pos = position(at: hitPoint, in: layout, doc: doc)

        // "First\nSecond" — second item starts at UTF-16 offset 6 (5 + 1 separator)
        let firstItemEnd = "First".utf16.count + 1  // +1 for separator "\n"
        #expect(pos.index >= firstItemEnd,
                "Hit inside second item should give index >= \(firstItemEnd), got \(pos.index)")
    }

    // ------------------------------------------------------------------
    // 4.4-J: hit-test inside a quote returns position within quoted text
    // ------------------------------------------------------------------
    @Test("hit-test inside a quote returns position within quote")
    func hitTestInsideQuote() {
        let innerDoc = TextDocument(blocks: [paraBlock("Quoted")])
        let doc = TextDocument(blocks: [.quote(innerDoc)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .quote(_, let innerLayout, _) = layout.blocks[0] else {
            Issue.record("expected .quote block"); return
        }
        guard case .text(let rect, _) = innerLayout.blocks[0] else {
            Issue.record("inner block[0] not text"); return
        }

        // Hit in the middle of the quoted text
        let hitPoint = CGPoint(x: rect.midX, y: rect.midY)
        let pos = position(at: hitPoint, in: layout, doc: doc)

        // "Quoted" is at UTF-16 offset 0 (single-block doc, no prefix paragraph)
        // Position should be within [0, 6] (length of "Quoted")
        let quotedLen = "Quoted".utf16.count
        #expect(pos.index >= 0 && pos.index <= quotedLen,
                "Hit inside quote should give index in [0, \(quotedLen)], got \(pos.index)")
    }

    // ------------------------------------------------------------------
    // 4.4-K: selection in first item only — rects don't overlap second item region
    // ------------------------------------------------------------------
    @Test("selectionRects for first item only stays within first item y-range")
    func selectionFirstItemOnly() {
        let list = List(marker: .bullet, isTight: true, items: [
            itemDoc("First"),
            itemDoc("Second")
        ])
        let doc = TextDocument(blocks: [.list(list)])
        let layout = LayoutEngine.layout(doc, width: 400)

        // "First\nSecond" — select only "First" (indices 0..5)
        let range = TextRange(
            start: TextPosition(index: 0),
            end: TextPosition(index: "First".utf16.count)
        )
        let rects = selectionRects(for: range, in: layout, doc: doc)
        #expect(!rects.isEmpty, "First item selection should return rects")

        // Get second item y-range to verify no rect extends into it
        guard case .list(_, let itemLayouts, _, _) = layout.blocks[0],
              itemLayouts.count >= 2 else { return }
        if case .text(let secondRect, _) = itemLayouts[1].blocks[0] {
            for rect in rects {
                #expect(rect.maxY <= secondRect.minY + 1,
                        "Selection rect \(rect) should not extend into second item at y=\(secondRect.minY)")
            }
        }
    }
}
