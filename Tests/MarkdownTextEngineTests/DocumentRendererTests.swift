import Testing
import CoreText
import CoreGraphics
@testable import MarkdownTextEngine

// MARK: - Test helpers

/// Builds a one-line "Hello World" layout in a 400×60 document space.
/// Font size 20 black on white.
private func makeOneParaLayout() -> (layout: DocumentLayout, doc: TextDocument) {
    let style = TextStyle(fontSize: 20, color: CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    let doc = TextDocument(blocks: [
        .paragraph(Paragraph(runs: [.text("Hello World", style)], style: .body))
    ])
    let layout = LayoutEngine.layout(doc, width: 400)
    return (layout, doc)
}

// MARK: - Tests

@Suite("DocumentRenderer pixel-level assertions")
struct DocumentRendererTests {

    // ------------------------------------------------------------------ //
    // Test 1: background region is the white fill color AND glyphs drew ink
    // ------------------------------------------------------------------ //
    @Test("background outside text is white; glyph zone has ink after rendering")
    func backgroundIsWhite() throws {
        let w = 400; let h = 100
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext")
            return
        }
        defer { buffer.deallocate() }

        let (layout, _) = makeOneParaLayout()

        // -- BEFORE rendering: sample a pixel in the glyph zone (rows 0..20, cols 0..150).
        // The buffer was pre-filled with white, so it must be white before draw().
        var allWhiteBefore = true
        outerBefore: for y in 0..<20 {
            for x in 0..<150 {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    allWhiteBefore = false
                    break outerBefore
                }
            }
        }
        #expect(allWhiteBefore, "Glyph zone should be white BEFORE rendering")

        // Render with no selection
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)), selection: [])

        // -- AFTER rendering: the bottom-right corner should still be white (renderer never fills background).
        let pxCorner = pixel(at: 390, y: 90, width: w, buffer: buffer)
        #expect(pxCorner.r == 255, "Background corner should remain white after rendering")
        #expect(pxCorner.g == 255, "Background corner should remain white after rendering")
        #expect(pxCorner.b == 255, "Background corner should remain white after rendering")
        #expect(pxCorner.a == 255, "Background corner should remain white after rendering")

        // -- AFTER rendering: the glyph zone (rows 0..20, cols 0..150) must contain ink.
        var foundInkAfter = false
        outerAfter: for y in 0..<20 {
            for x in 0..<150 {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundInkAfter = true
                    break outerAfter
                }
            }
        }
        #expect(foundInkAfter, "Glyph zone should contain ink pixels AFTER rendering")
    }

    // ------------------------------------------------------------------ //
    // Test 2: text region has non-white pixels (glyphs drew ink)
    // ------------------------------------------------------------------ //
    @Test("text region contains non-white ink pixels after rendering")
    func textRegionHasInk() throws {
        // Use a taller canvas so the flip arithmetic has room.
        let w = 400; let h = 100
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext")
            return
        }
        defer { buffer.deallocate() }

        let (layout, _) = makeOneParaLayout()
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)), selection: [])

        // Inspect a horizontal band near the top where text glyphs land.
        // Sample all pixels in rows 0..30, columns 0..200, look for any non-white pixel.
        var foundInk = false
        outer: for y in 0..<40 {
            for x in 0..<200 {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                // A non-white pixel means ink was placed
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundInk = true
                    break outer
                }
            }
        }
        #expect(foundInk, "Expected ink pixels from rendered glyphs, but found none")
    }

    // ------------------------------------------------------------------ //
    // Test 3: selection rect produces highlight-colored pixels
    // ------------------------------------------------------------------ //
    @Test("selection rect region contains selection highlight color")
    func selectionRectContainsHighlight() throws {
        let w = 400; let h = 100
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext")
            return
        }
        defer { buffer.deallocate() }

        let (layout, _) = makeOneParaLayout()
        // Pass a selection rect covering the first 120px wide × full-height stripe at top-left.
        let selectionRect = CGRect(x: 0, y: 0, width: 120, height: 30)
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)), selection: [selectionRect])

        // DocumentRenderer draws selection with a blue-ish highlight (system blue ~0.2, 0.5, 1.0, 0.3).
        // After blending onto white, the blue channel should dominate relative to red.
        //
        // Coordinate mapping:
        //   - CGContext has canvasHeight = visible.maxY = 100.
        //   - Transform: translateBy(0, 100), scaleBy(1, -1).
        //   - Doc space y=0 → CG y=100 (top of canvas).
        //   - Doc space y=30 → CG y=70.
        //   - selectionRect (doc) y=0..30 → CG y=70..100.
        //   - In the bitmap (row 0 = bottom in CG), CG y=70..100 → bitmap rows 0..30 (top of image).
        //   - With standard CGContext bitmap (y-up in CG, row 0 at bottom of CG = row 0 at top of MEMORY
        //     ONLY when using kCGBitmapByteOrderDefault with no flip), we need to verify carefully.
        //
        // CGContext with standard orientation:
        //   row 0 in memory = CG y = (height-1) = 99 (top pixel of CG space).
        //   So CG y=70..99 → memory rows 0..29 (top portion of bitmap).
        // Scan rows 0..29 in memory for blue-tinted pixels.
        var foundHighlight = false
        for y in 0..<30 {
            for x in 10..<100 {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                // A tinted pixel: blue channel noticeably > red channel means selection highlight applied.
                if Int(px.b) > Int(px.r) + 5 {
                    foundHighlight = true
                    break
                }
            }
            if foundHighlight { break }
        }
        #expect(foundHighlight, "Expected blue-tinted selection highlight pixels, but found none")
    }

    // ------------------------------------------------------------------ //
    // Test 4: rendering with no blocks produces no errors (empty document)
    // ------------------------------------------------------------------ //
    @Test("drawing an empty layout does not crash and leaves buffer untouched")
    func emptyLayoutNoOp() throws {
        let w = 100; let h = 100
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext")
            return
        }
        defer { buffer.deallocate() }

        let emptyLayout = DocumentLayout(blocks: [], contentSize: .zero)
        // Must not crash
        DocumentRenderer.draw(emptyLayout, in: ctx, canvasHeight: CGFloat(h), visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)), selection: [])
        // Buffer still all white
        let px = pixel(at: 50, y: 50, width: w, buffer: buffer)
        #expect(px.r == 255 && px.g == 255 && px.b == 255)
    }

    // ------------------------------------------------------------------ //
    // Test 5: visible rect culling — block outside visible range adds no ink
    // ------------------------------------------------------------------ //
    @Test("block outside visible rect is not rendered")
    func cullingOutsideVisible() throws {
        let w = 400; let h = 60
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext")
            return
        }
        defer { buffer.deallocate() }

        let (layout, _) = makeOneParaLayout()
        // Visible rect starts at y=500 — far below the text block which is at y≈0
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: CGRect(x: 0, y: 500, width: CGFloat(w), height: CGFloat(h)), selection: [])

        // Entire buffer should still be white
        var foundInk = false
        for y in 0..<h {
            for x in 0..<w {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundInk = true
                }
            }
        }
        #expect(!foundInk, "Expected no ink when block is outside the visible rect")
    }

    // ------------------------------------------------------------------ //
    // Test 6: scroll-window — canvasHeight drives the flip, not visible.maxY
    //
    // Regression test for the bug where `visible.maxY` was used as the flip
    // height instead of `canvasHeight`.  When the view is scrolled so that
    // `visible` has a non-zero origin (simulating a scroll window), glyphs must
    // land at the SAME pixel rows as when `visible` covers the full canvas.
    //
    // The test renders the same layout twice into two identical bitmaps:
    //   A) visible == full canvas (baseline)
    //   B) visible == a sub-rect whose origin.y > 0 (simulating scroll)
    // Both calls receive the same `canvasHeight` (full bitmap height).
    // The ink pixels must be identical between A and B.
    //
    // NOTE: With the old `visible.maxY` formula, call B would use a smaller
    // canvasHeight (visible.maxY < actual height), placing glyphs at wrong
    // rows — the buffers would differ, causing the test to fail.
    // ------------------------------------------------------------------ //
    @Test("scroll window: canvasHeight drives y-flip, not visible.maxY")
    func scrollWindowFlipUsesCanvasHeight() throws {
        // Use a tall canvas so the layout sits well within it and there is
        // enough room for a meaningful scroll sub-rect below the text.
        let w = 400; let h = 300
        let fullVisible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        // A scroll window that starts 100pt below the top — visible.maxY = 200,
        // which is less than canvasHeight (300).  The old code would have used
        // 200 for the flip, misplacing glyphs.
        let scrollVisible = CGRect(x: 0, y: 100, width: CGFloat(w), height: 100)

        let (layout, _) = makeOneParaLayout()

        // -- Bitmap A: full visible rect (baseline) --
        guard let (ctxA, bufferA) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext A"); return
        }
        defer { bufferA.deallocate() }
        DocumentRenderer.draw(layout, in: ctxA, canvasHeight: CGFloat(h), visible: fullVisible, selection: [])

        // -- Bitmap B: scrolled visible rect, same canvasHeight --
        guard let (ctxB, bufferB) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext B"); return
        }
        defer { bufferB.deallocate() }
        DocumentRenderer.draw(layout, in: ctxB, canvasHeight: CGFloat(h), visible: scrollVisible, selection: [])

        // Collect ink pixels from A (rows 0..50, cols 0..200 — glyph zone).
        var inkRowsA: Set<Int> = []
        for y in 0..<50 {
            for x in 0..<200 {
                let px = pixel(at: x, y: y, width: w, buffer: bufferA)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    inkRowsA.insert(y)
                }
            }
        }
        #expect(!inkRowsA.isEmpty, "Bitmap A (full visible) must contain ink in glyph zone")

        // Collect ink pixels from B in the SAME absolute pixel rows.
        // Because B's visible window starts at y=100 in document space and the
        // text block is near y=0, the culling will skip the text — that's correct
        // behaviour.  What we actually verify is that when B's visible window
        // DOES include the text block (use a window that covers y=0..100 as
        // well), glyphs land at the same rows as in A.
        //
        // Re-render B with a window that includes the text (origin.y = 0, height
        // < canvasHeight so visible.maxY != canvasHeight).
        guard let (ctxB2, bufferB2) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext B2"); return
        }
        defer { bufferB2.deallocate() }
        // visible starts at y=0 but only covers 150pt out of 300pt canvas.
        // Old code: canvasHeight = visible.maxY = 150  → wrong flip.
        // New code: canvasHeight = 300               → correct flip.
        let partialVisible = CGRect(x: 0, y: 0, width: CGFloat(w), height: 150)
        DocumentRenderer.draw(layout, in: ctxB2, canvasHeight: CGFloat(h), visible: partialVisible, selection: [])

        // Ink rows in B2 must match those in A.
        var inkRowsB2: Set<Int> = []
        for y in 0..<50 {
            for x in 0..<200 {
                let px = pixel(at: x, y: y, width: w, buffer: bufferB2)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    inkRowsB2.insert(y)
                }
            }
        }
        #expect(!inkRowsB2.isEmpty, "Bitmap B2 (partial visible, full canvasHeight) must contain ink in glyph zone")
        #expect(inkRowsA == inkRowsB2, "Glyph ink must land at the same pixel rows regardless of visible.maxY")
    }
}
