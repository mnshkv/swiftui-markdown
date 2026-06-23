import Testing
import CoreGraphics
@testable import MarkdownTextEngine

/// Reads one RGBA pixel from a raw RGBA8 bitmap buffer.
private func edgePixel(at x: Int, y: Int, width: Int, buffer: UnsafeMutableRawPointer) -> (r: UInt8, g: UInt8, b: UInt8) {
    let offset = (y * width + x) * 4
    let p = buffer.assumingMemoryBound(to: UInt8.self)
    return (p[offset], p[offset + 1], p[offset + 2])
}

@Suite("Edge cases")
struct EdgeCaseTests {

    // MARK: - 1. Thematic break layout

    @Test("thematic break layout: single rule block with correct rect")
    func thematicBreakLayout() {
        let ruleStyle = RuleStyle(thickness: 2, color: CGColor(gray: 0.5, alpha: 1))
        let doc = TextDocument(blocks: [.thematicBreak(ruleStyle)])
        let layout = LayoutEngine.layout(doc, width: 200)

        #expect(layout.blocks.count == 1)

        guard case .rule(let rect) = layout.blocks[0] else {
            Issue.record("Expected .rule block, got \(layout.blocks[0])")
            return
        }
        #expect(rect.height == 2, "Rule height must equal thickness (2)")
        #expect(rect.width == 200, "Rule width must equal canvas width (200)")
        #expect(layout.contentSize.height == 2, "contentSize.height must equal rule thickness")
    }

    // MARK: - 2. Thematic break renders ink

    @Test("thematic break renders grey ink in the rule rect")
    func thematicBreakRendersInk() {
        let ruleStyle = RuleStyle(thickness: 2, color: CGColor(gray: 0.5, alpha: 1))
        let doc = TextDocument(blocks: [.thematicBreak(ruleStyle)])
        let layout = LayoutEngine.layout(doc, width: 200)

        // Build a 200×40 RGBA8 context pre-filled with white.
        let w = 200; let h = 40
        let bytesPerRow = w * 4
        let bufferSize = h * bytesPerRow
        let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { rawBuffer.deallocate() }
        rawBuffer.initializeMemory(as: UInt8.self, repeating: 0xFF, count: bufferSize)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: rawBuffer,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            Issue.record("Could not create CGContext")
            return
        }

        // Rule is at doc y=0..2, canvasHeight=40.
        // After y-flip (translateBy(0,40), scaleBy(1,-1)):
        //   doc y=0 → CG y=40, doc y=2 → CG y=38.
        // In the bitmap, row 0 in memory = highest CG y (y=40→39).
        // So CG y=38..40 maps to bitmap rows 0..1.
        DocumentRenderer.draw(
            layout,
            in: ctx,
            canvasHeight: CGFloat(h),
            visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
            selection: []
        )

        // Check bitmap rows 0..1 for non-white pixels (grey ink, RGB < 220).
        var foundInk = false
        outer: for row in 0..<2 {
            for col in 0..<w {
                let px = edgePixel(at: col, y: row, width: w, buffer: rawBuffer)
                if px.r < 220 && px.g < 220 && px.b < 220 {
                    foundInk = true
                    break outer
                }
            }
        }
        #expect(foundInk, "Expected grey ink in bitmap rows 0..1 where the rule was drawn")
    }

    // MARK: - 3. Empty document

    @Test("empty document: contentSize.height == 0 and no blocks")
    func emptyDocument() {
        let layout = LayoutEngine.layout(TextDocument(blocks: []), width: 200)
        #expect(layout.contentSize.height == 0, "Empty doc must have zero height")
        #expect(layout.blocks.isEmpty, "Empty doc must have no blocks")
    }

    // MARK: - 4. Degenerate width: zero

    @Test("degenerate width zero: layout does not crash and contentSize is finite")
    func degenerateWidthZero() {
        let style = TextStyle(fontSize: 14, color: CGColor(gray: 0, alpha: 1))
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Hello", style)], style: .body))
        ])
        let layout = LayoutEngine.layout(doc, width: 0)
        #expect(layout.contentSize.width.isFinite, "contentSize.width must be finite for width=0")
        #expect(layout.contentSize.height.isFinite, "contentSize.height must be finite for width=0")
    }

    // MARK: - 5. Degenerate width: negative

    @Test("degenerate width negative: layout does not crash and contentSize is finite")
    func degenerateWidthNegative() {
        let style = TextStyle(fontSize: 14, color: CGColor(gray: 0, alpha: 1))
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Hello", style)], style: .body))
        ])
        let layout = LayoutEngine.layout(doc, width: -10)
        #expect(layout.contentSize.width.isFinite, "contentSize.width must be finite for width=-10")
        #expect(layout.contentSize.height.isFinite, "contentSize.height must be finite for width=-10")
    }
}
