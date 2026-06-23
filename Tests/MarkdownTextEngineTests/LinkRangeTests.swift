import Testing
import CoreGraphics
import CoreText
@testable import MarkdownTextEngine

// MARK: - Task 7.4: linkRange pure helper + pressed-link render snapshot tests

@Suite("linkRange helper and pressed-link highlight (Task 7.4)")
struct LinkRangeTests {

    // Builds a document with a single paragraph: "Click [here](url) now"
    // where "here" (4 chars, UTF-16 offsets 6..10) is a link with payload "url".
    private func makeLinkDoc() -> (layout: DocumentLayout, doc: TextDocument) {
        let s = TextStyle(fontSize: 17, color: .black)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [
                .text("Click ", s),
                .link(runs: [.text("here", s)], payload: LinkPayload("url")),
                .text(" now", s)
            ], style: .body))
        ])
        let layout = LayoutEngine.layout(doc, width: 400)
        return (layout, doc)
    }

    // MARK: - linkRange pure-helper unit tests

    @Test("linkRange on a non-link region returns nil")
    func linkRangeOffLink() {
        let (layout, doc) = makeLinkDoc()
        guard case .text(_, let lines) = layout.blocks[0], let line = lines.first else {
            Issue.record("expected a text block with at least one line")
            return
        }
        // x close to 0 lands in "Click " (not a link).
        let pt = CGPoint(x: line.origin.x + 2, y: line.origin.y + line.size.height / 2)
        let result = linkRange(at: pt, layout: layout, doc: doc)
        #expect(result == nil, "non-link region should return nil")
    }

    @Test("linkRange on the link text returns the correct payload and range")
    func linkRangeOnLink() {
        let (layout, doc) = makeLinkDoc()
        guard case .text(_, let lines) = layout.blocks[0], let line = lines.first else {
            Issue.record("expected a text block with at least one line")
            return
        }
        // "Click " is 6 chars (UTF-16); "here" starts at offset 6.
        // Use CTLine to get an x-coordinate inside "here".
        let hereStartX = CTLineGetOffsetForStringIndex(line.ctLine, 6, nil)
        // Tap 3pt into "here".
        let pt = CGPoint(x: line.origin.x + hereStartX + 3, y: line.origin.y + line.size.height / 2)
        guard let result = linkRange(at: pt, layout: layout, doc: doc) else {
            Issue.record("expected linkRange to return a result for a point on a link")
            return
        }
        #expect(result.payload == LinkPayload("url"))
        // "here" has 4 UTF-16 units; it starts at offset 6 in the paragraph.
        #expect(result.range.start.index == 6)
        #expect(result.range.end.index == 10)
    }

    @Test("linkRange for a point far below all text returns nil")
    func linkRangeBelowText() {
        let (layout, doc) = makeLinkDoc()
        let pt = CGPoint(x: 50, y: 9999)
        let result = linkRange(at: pt, layout: layout, doc: doc)
        // The hit snaps to the end of the document text (non-link region),
        // so result should be nil.
        #expect(result == nil)
    }

    // MARK: - Pressed-link render snapshot test

    /// Tests that drawing with a `pressedLinkRects` argument produces a visually
    /// distinct (darker blue) highlight compared to no highlight.
    @Test("pressed-link rects produce a darker-blue highlight in the rendered bitmap")
    func pressedLinkHighlightAppearsInBitmap() throws {
        let w = 400; let h = 100
        let (layout, _) = makeLinkDoc()

        // A rect covering the left quarter of the canvas — just needs to be in the visible area.
        let pressedRect = CGRect(x: 0, y: 0, width: 80, height: 30)

        // Baseline: render WITHOUT pressedLinkRects
        guard let (ctxA, bufferA) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext A"); return
        }
        defer { bufferA.deallocate() }
        DocumentRenderer.draw(layout, in: ctxA, canvasHeight: CGFloat(h),
                              visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
                              selection: [], pressedLinkRects: [])

        // Test: render WITH pressedLinkRects
        guard let (ctxB, bufferB) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext B"); return
        }
        defer { bufferB.deallocate() }
        DocumentRenderer.draw(layout, in: ctxB, canvasHeight: CGFloat(h),
                              visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
                              selection: [], pressedLinkRects: [pressedRect])

        // Scan the full bitmap for any pixel in B that has blue channel > red channel,
        // indicating the pressed-link fill (blue-tinted, alpha=0.5 on white → blue dominant).
        var foundPressHighlight = false
        outerTint: for y in 0..<h {
            for x in 0..<w {
                let pxB = pixel(at: x, y: y, width: w, buffer: bufferB)
                if Int(pxB.b) > Int(pxB.r) + 5 {
                    foundPressHighlight = true
                    break outerTint
                }
            }
        }
        #expect(foundPressHighlight,
                "Expected pressed-link highlight (blue-dominant pixels) but found none")
    }
}

// MARK: - Bitmap helpers are provided by PixelSupport.swift (module-level)
