import Testing
import CoreText
import CoreGraphics
@testable import MarkdownTextEngine

// MARK: - Pixel-level snapshot assertions

/// Reads one RGBA pixel from a raw RGBA8 bitmap buffer.
private func pixel(at x: Int, y: Int, width: Int, buffer: UnsafeMutableRawPointer) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    let offset = (y * width + x) * 4
    let p = buffer.assumingMemoryBound(to: UInt8.self)
    return (p[offset], p[offset + 1], p[offset + 2], p[offset + 3])
}

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

/// Creates a 400×60 RGBA8 CGContext pre-filled with white.
private func makeWhiteContext(width: Int = 400, height: Int = 60)
    -> (ctx: CGContext, buffer: UnsafeMutableRawPointer)?
{
    let bytesPerRow = width * 4
    let bufferSize = height * bytesPerRow
    let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
    // Fill white (0xFF each channel)
    rawBuffer.initializeMemory(as: UInt8.self, repeating: 0xFF, count: bufferSize)

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
            data: rawBuffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        rawBuffer.deallocate()
        return nil
    }
    return (ctx, rawBuffer)
}

// MARK: - Tests

@Suite("DocumentRenderer pixel-level assertions")
struct DocumentRendererTests {

    // ------------------------------------------------------------------ //
    // Test 1: background region is the white fill color
    // ------------------------------------------------------------------ //
    @Test("background outside text is white (unfilled by renderer)")
    func backgroundIsWhite() throws {
        guard let (ctx, buffer) = makeWhiteContext() else {
            Issue.record("Could not create CGContext")
            return
        }
        defer { buffer.deallocate() }

        let (layout, _) = makeOneParaLayout()
        // Render with no selection
        DocumentRenderer.draw(layout, in: ctx, visible: CGRect(x: 0, y: 0, width: 400, height: 60), selection: [])

        // Sample a few pixels in the bottom-right corner where no text should be.
        // With a 400×60 bitmap, y=58 x=390 should be white (renderer doesn't fill).
        let px = pixel(at: 390, y: 58, width: 400, buffer: buffer)
        // White = (255, 255, 255, 255) in premultiplied RGBA
        #expect(px.r == 255)
        #expect(px.g == 255)
        #expect(px.b == 255)
        #expect(px.a == 255)
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
        DocumentRenderer.draw(layout, in: ctx, visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)), selection: [])

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
        DocumentRenderer.draw(layout, in: ctx, visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)), selection: [selectionRect])

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
        DocumentRenderer.draw(emptyLayout, in: ctx, visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)), selection: [])
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
        DocumentRenderer.draw(layout, in: ctx, visible: CGRect(x: 0, y: 500, width: CGFloat(w), height: CGFloat(h)), selection: [])

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
}
