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

private func bulletItem(_ text: String) -> TextDocument {
    TextDocument(blocks: [paraBlock(text)])
}

// MARK: - Task 4.1 List Layout Tests

@Suite("List layout (Task 4.1)")
struct ListLayoutTests {

    // ------------------------------------------------------------------
    // 4.1-A: item content x-offset == listItemIndent from block left edge
    // ------------------------------------------------------------------
    @Test("bullet list: item content x-offset equals listItemIndent")
    func bulletItemXOffset() {
        let list = List(marker: .bullet, isTight: true, items: [
            bulletItem("First item"),
            bulletItem("Second item")
        ])
        let doc = TextDocument(blocks: [.list(list)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .list(_, let itemLayouts, _, _) = layout.blocks[0] else {
            Issue.record("expected .list block"); return
        }
        #expect(itemLayouts.count == 2)

        // Each item's first text block should have x-origin == listItemIndent
        for (i, itemLayout) in itemLayouts.enumerated() {
            guard case .text(let rect, let lines) = itemLayout.blocks[0] else {
                Issue.record("item \(i) block[0] is not .text"); continue
            }
            // The rect and line origins should be offset by listItemIndent from the doc left
            #expect(rect.origin.x == listItemIndent,
                    "item \(i) rect.origin.x should equal listItemIndent (\(listItemIndent))")
            if let firstLine = lines.first {
                #expect(firstLine.origin.x == listItemIndent,
                        "item \(i) first line x should equal listItemIndent")
            }
        }
    }

    // ------------------------------------------------------------------
    // 4.1-B: ordered list produces correct marker strings (start: 3 → "3.", "4.")
    // ------------------------------------------------------------------
    @Test("ordered list: markers numbered from start")
    func orderedListMarkers() {
        let list = List(marker: .ordered(start: 3), isTight: true, items: [
            bulletItem("Alpha"),
            bulletItem("Beta")
        ])
        let doc = TextDocument(blocks: [.list(list)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .list(_, _, _, let markerStrings) = layout.blocks[0] else {
            Issue.record("expected .list block"); return
        }
        #expect(markerStrings.count == 2)
        #expect(markerStrings[0] == "3.")
        #expect(markerStrings[1] == "4.")
    }

    // ------------------------------------------------------------------
    // 4.1-C: marker frames are to the left of item content
    // ------------------------------------------------------------------
    @Test("marker frames are left of item content")
    func markerFramesLeftOfContent() {
        let list = List(marker: .bullet, isTight: true, items: [
            bulletItem("Item one"),
            bulletItem("Item two")
        ])
        let doc = TextDocument(blocks: [.list(list)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .list(_, let itemLayouts, let markerFrames, _) = layout.blocks[0] else {
            Issue.record("expected .list block"); return
        }
        #expect(markerFrames.count == itemLayouts.count)

        for (i, markerFrame) in markerFrames.enumerated() {
            // Marker x must be < listItemIndent
            #expect(markerFrame.origin.x < listItemIndent,
                    "marker \(i) should start to the left of item indent")
            // Marker right edge should be ≤ listItemIndent
            #expect(markerFrame.maxX <= listItemIndent + 1,  // +1 for rounding
                    "marker \(i) right edge should not exceed indent width")
        }
    }

    // ------------------------------------------------------------------
    // 4.1-D: empty list doesn't crash and has zero height
    // ------------------------------------------------------------------
    @Test("empty list produces zero-height block without crashing")
    func emptyList() {
        let list = List(marker: .bullet, isTight: true, items: [])
        let doc = TextDocument(blocks: [.list(list)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .list(let rect, let itemLayouts, _, _) = layout.blocks[0] else {
            Issue.record("expected .list block"); return
        }
        #expect(rect.height == 0)
        #expect(itemLayouts.isEmpty)
    }

    // ------------------------------------------------------------------
    // 4.1-E: nested list (item containing a list) indents twice
    // ------------------------------------------------------------------
    @Test("nested list: inner list indents by 2x listItemIndent")
    func nestedListDoubleIndent() {
        // Outer list item contains a nested list
        let innerList = List(marker: .bullet, isTight: true, items: [
            bulletItem("Inner item")
        ])
        let outerItemDoc = TextDocument(blocks: [
            paraBlock("Outer text"),
            .list(innerList)
        ])
        let outerList = List(marker: .bullet, isTight: true, items: [outerItemDoc])
        let doc = TextDocument(blocks: [.list(outerList)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .list(_, let outerItemLayouts, _, _) = layout.blocks[0] else {
            Issue.record("expected outer .list block"); return
        }
        guard let outerItemLayout = outerItemLayouts.first else {
            Issue.record("outer list has no items"); return
        }
        // Find the nested list block inside the outer item
        guard case .list(_, let innerItemLayouts, _, _) = outerItemLayout.blocks[1] else {
            Issue.record("outer item block[1] is not .list"); return
        }
        guard let innerItemLayout = innerItemLayouts.first else {
            Issue.record("inner list has no items"); return
        }
        // Inner item's text should be offset by 2x listItemIndent from x=0
        guard case .text(let innerRect, _) = innerItemLayout.blocks[0] else {
            Issue.record("inner item block[0] is not .text"); return
        }
        let expectedOffset = listItemIndent * 2
        #expect(innerRect.origin.x == expectedOffset,
                "inner item x should be 2x listItemIndent (\(expectedOffset)), got \(innerRect.origin.x)")
    }

    // ------------------------------------------------------------------
    // 4.1-F: list block height equals sum of item heights (tight list)
    // ------------------------------------------------------------------
    @Test("tight list block height equals sum of item heights")
    func tightListHeight() {
        let list = List(marker: .bullet, isTight: true, items: [
            bulletItem("Item A"),
            bulletItem("Item B")
        ])
        let doc = TextDocument(blocks: [.list(list)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .list(let listRect, let itemLayouts, _, _) = layout.blocks[0] else {
            Issue.record("expected .list block"); return
        }
        let sumOfItemHeights = itemLayouts.reduce(0) { $0 + $1.contentSize.height }
        #expect(abs(listRect.height - sumOfItemHeights) < 1,
                "list height \(listRect.height) should equal sum of item heights \(sumOfItemHeights)")
    }

    // ------------------------------------------------------------------
    // 4.1-G: items are stacked vertically (item i+1 y >= item i maxY)
    // ------------------------------------------------------------------
    @Test("list items are stacked vertically without overlap")
    func itemsStackedVertically() {
        let list = List(marker: .bullet, isTight: true, items: [
            bulletItem("First"),
            bulletItem("Second"),
            bulletItem("Third")
        ])
        let doc = TextDocument(blocks: [.list(list)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .list(_, let itemLayouts, _, _) = layout.blocks[0] else {
            Issue.record("expected .list block"); return
        }
        #expect(itemLayouts.count == 3)

        var prevMaxY: CGFloat = -1
        for (i, itemLayout) in itemLayouts.enumerated() {
            guard case .text(let rect, _) = itemLayout.blocks[0] else { continue }
            #expect(rect.origin.y >= prevMaxY,
                    "item \(i) y origin \(rect.origin.y) should be >= previous item maxY \(prevMaxY)")
            prevMaxY = rect.maxY
        }
    }
}

// MARK: - Task 4.2 Quote Layout Tests

@Suite("Quote layout (Task 4.2)")
struct QuoteLayoutTests {

    // ------------------------------------------------------------------
    // 4.2-A: inner content x-offset == quoteIndent
    // ------------------------------------------------------------------
    @Test("block quote: inner content x-offset equals quoteIndent")
    func quoteInnerXOffset() {
        let innerDoc = TextDocument(blocks: [paraBlock("Quoted text")])
        let doc = TextDocument(blocks: [.quote(innerDoc)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .quote(_, let innerLayout, _) = layout.blocks[0] else {
            Issue.record("expected .quote block"); return
        }
        guard case .text(let innerRect, let lines) = innerLayout.blocks[0] else {
            Issue.record("inner block[0] is not .text"); return
        }
        #expect(innerRect.origin.x == quoteIndent,
                "inner rect x should equal quoteIndent (\(quoteIndent))")
        if let firstLine = lines.first {
            #expect(firstLine.origin.x == quoteIndent,
                    "inner first line x should equal quoteIndent")
        }
    }

    // ------------------------------------------------------------------
    // 4.2-B: bar rect geometry
    // ------------------------------------------------------------------
    @Test("bar rect: x≈0, width is small, height equals inner content height")
    func barRectGeometry() {
        let innerDoc = TextDocument(blocks: [paraBlock("Some quoted text here")])
        let doc = TextDocument(blocks: [.quote(innerDoc)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .quote(let quoteRect, let innerLayout, let barRect) = layout.blocks[0] else {
            Issue.record("expected .quote block"); return
        }
        #expect(barRect.origin.x == 0, "bar rect x should be 0 (left edge)")
        #expect(barRect.width == quoteBarWidth, "bar width should equal quoteBarWidth (\(quoteBarWidth))")
        #expect(barRect.width < quoteIndent, "bar width should be less than quoteIndent")
        // Bar height should match the inner content height
        let innerHeight = innerLayout.contentSize.height
        #expect(abs(barRect.height - innerHeight) < 1,
                "bar height \(barRect.height) should equal inner content height \(innerHeight)")
        // Quote block height should also match inner content height
        #expect(abs(quoteRect.height - innerHeight) < 1,
                "quote rect height \(quoteRect.height) should equal inner content height \(innerHeight)")
    }

    // ------------------------------------------------------------------
    // 4.2-C: nested quote double-indents
    // ------------------------------------------------------------------
    @Test("nested quote: inner content x-offset equals 2 * quoteIndent")
    func nestedQuoteDoubleIndent() {
        let innerInnerDoc = TextDocument(blocks: [paraBlock("Deep text")])
        let innerDoc = TextDocument(blocks: [.quote(innerInnerDoc)])
        let doc = TextDocument(blocks: [.quote(innerDoc)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .quote(_, let outerInnerLayout, _) = layout.blocks[0] else {
            Issue.record("expected outer .quote block"); return
        }
        guard case .quote(_, let deepLayout, _) = outerInnerLayout.blocks[0] else {
            Issue.record("expected inner .quote block"); return
        }
        guard case .text(let deepRect, _) = deepLayout.blocks[0] else {
            Issue.record("deep block[0] is not .text"); return
        }
        let expectedOffset = quoteIndent * 2
        #expect(deepRect.origin.x == expectedOffset,
                "deep text x should be 2x quoteIndent (\(expectedOffset)), got \(deepRect.origin.x)")
    }

    // ------------------------------------------------------------------
    // 4.2-D: empty quote doesn't crash
    // ------------------------------------------------------------------
    @Test("empty block quote produces zero-height block without crashing")
    func emptyQuote() {
        let emptyDoc = TextDocument(blocks: [])
        let doc = TextDocument(blocks: [.quote(emptyDoc)])
        let layout = LayoutEngine.layout(doc, width: 400)

        guard case .quote(let rect, _, _) = layout.blocks[0] else {
            Issue.record("expected .quote block"); return
        }
        #expect(rect.height == 0)
    }
}
