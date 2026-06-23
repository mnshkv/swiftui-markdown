import Testing
import CoreText
import CoreGraphics
@testable import MarkdownTextEngine

// MARK: - Helpers (shared via PixelSupport.swift)

private func textStyle() -> TextStyle {
    TextStyle(fontSize: 17, color: CGColor(red: 0, green: 0, blue: 0, alpha: 1))
}

private func paraBlock(_ text: String) -> Block {
    .paragraph(Paragraph(runs: [.text(text, textStyle())], style: .body))
}

// MARK: - Task 4.3: Renderer tests for lists and quotes

@Suite("List and quote rendering (Task 4.3)")
struct ListQuoteRendererTests {

    // ------------------------------------------------------------------
    // 4.3-A: Bullet glyph appears in marker region
    // ------------------------------------------------------------------
    @Test("bullet marker region has ink after rendering")
    func bulletMarkerHasInk() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let list = List(marker: .bullet, isTight: true, items: [
            TextDocument(blocks: [paraBlock("Hello list item")])
        ])
        let doc = TextDocument(blocks: [.list(list)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // The marker (•) should be drawn at x < listItemIndent.
        // Scan the first ~60 rows, x 0..23 (before the indent) for ink.
        var foundMarkerInk = false
        outer: for y in 0..<60 {
            for x in 0..<Int(listItemIndent) {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundMarkerInk = true
                    break outer
                }
            }
        }
        #expect(foundMarkerInk, "Marker region (x < listItemIndent) should have ink pixels from bullet glyph")
    }

    // ------------------------------------------------------------------
    // 4.3-B: Item content appears to the right of the marker indent
    // ------------------------------------------------------------------
    @Test("list item content region has ink to the right of indent")
    func listItemContentHasInk() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let list = List(marker: .bullet, isTight: true, items: [
            TextDocument(blocks: [paraBlock("Hello list item")])
        ])
        let doc = TextDocument(blocks: [.list(list)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // Content should appear at x >= listItemIndent
        let indentInt = Int(listItemIndent)
        var foundContentInk = false
        outer: for y in 0..<60 {
            for x in indentInt..<(indentInt + 150) {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundContentInk = true
                    break outer
                }
            }
        }
        #expect(foundContentInk, "Content region (x >= listItemIndent) should have ink pixels")
    }

    // ------------------------------------------------------------------
    // 4.3-C: Quote bar region has ink (the grey vertical bar)
    // ------------------------------------------------------------------
    @Test("quote bar region has ink after rendering")
    func quoteBarHasInk() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let innerDoc = TextDocument(blocks: [paraBlock("Quoted text here")])
        let doc = TextDocument(blocks: [.quote(innerDoc)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // The bar is at x=0, width=quoteBarWidth — should have grey ink.
        let barWidth = Int(quoteBarWidth)
        var foundBarInk = false
        outer: for y in 0..<60 {
            for x in 0..<max(barWidth, 1) {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                // Grey ink: all channels < 255 but approximately equal
                if px.r < 230 || px.g < 230 || px.b < 230 {
                    foundBarInk = true
                    break outer
                }
            }
        }
        #expect(foundBarInk, "Quote bar region (x < quoteBarWidth) should have grey ink pixels")
    }

    // ------------------------------------------------------------------
    // 4.3-D: Quote content appears to the right of the quote indent
    // ------------------------------------------------------------------
    @Test("quote content has ink to the right of quoteIndent")
    func quoteContentHasInk() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let innerDoc = TextDocument(blocks: [paraBlock("Quoted text here")])
        let doc = TextDocument(blocks: [.quote(innerDoc)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        let indentInt = Int(quoteIndent)
        var foundInk = false
        outer: for y in 0..<60 {
            for x in indentInt..<(indentInt + 150) {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundInk = true
                    break outer
                }
            }
        }
        #expect(foundInk, "Quote content region (x >= quoteIndent) should have ink pixels")
    }

    // ------------------------------------------------------------------
    // 4.3-E: Empty list renders without crashing (no ink expected)
    // ------------------------------------------------------------------
    @Test("empty list renders without crash and leaves buffer white")
    func emptyListNoOp() {
        let w = 100; let h = 100
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let list = List(marker: .bullet, isTight: true, items: [])
        let doc = TextDocument(blocks: [.list(list)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        // Must not crash
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])
        // Buffer still all white (list is zero-height, nothing drawn)
        let px = pixel(at: 50, y: 50, width: w, buffer: buffer)
        #expect(px.r == 255 && px.g == 255 && px.b == 255)
    }

    // ------------------------------------------------------------------
    // 4.3-F: Multi-item list: both items produce ink somewhere in the content zone
    // ------------------------------------------------------------------
    @Test("multi-item ordered list renders with ink in content zone")
    func multiItemListBothRendered() {
        let w = 400; let h = 300
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let list = List(marker: .ordered(start: 1), isTight: true, items: [
            TextDocument(blocks: [paraBlock("First item")]),
            TextDocument(blocks: [paraBlock("Second item")])
        ])
        let doc = TextDocument(blocks: [.list(list)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // Scan the content region (x >= indent) across all rows for ink from both items
        let indentInt = Int(listItemIndent)
        var foundContentInk = false
        outerContent: for y in 0..<h {
            for x in indentInt..<(indentInt + 200) {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundContentInk = true
                    break outerContent
                }
            }
        }
        #expect(foundContentInk, "Multi-item list content region should have ink from at least one item")

        // Also check marker zone (x < indent) has ink (from "1." and "2.")
        var foundMarkerInk = false
        outerMarker: for y in 0..<h {
            for x in 0..<indentInt {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundMarkerInk = true
                    break outerMarker
                }
            }
        }
        #expect(foundMarkerInk, "Marker region should have ink from ordered list markers")
    }
}
