// Tests/MarkdownTextEngineTests/PillRenderTests.swift
import Testing
import CoreText
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("Custom-rule pill background rendering")
struct PillRenderTests {
    @Test("a run with a green background paints green pixels behind the text")
    func pillPaintsBackground() throws {
        let w = 400, h = 60
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let green = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        let style = TextStyle(fontSize: 20, color: CGColor(gray: 0, alpha: 1), background: green)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Tag", style)], style: .body))
        ])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h),
                              visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
                              selection: [])

        // The pill extends ~3pt left of the glyphs (pillPaddingH), so the top-left
        // zone should contain saturated-green pixels.
        var foundGreen = false
        outer: for y in 0..<20 {
            for x in 0..<60 {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.g > 200 && px.r < 120 && px.b < 120 { foundGreen = true; break outer }
            }
        }
        #expect(foundGreen, "Expected green pill pixels behind the tagged run")
    }

    @Test("a run with no background leaves the corner white (no regression)")
    func noBackgroundNoFill() throws {
        let w = 400, h = 60
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let style = TextStyle(fontSize: 20, color: CGColor(gray: 0, alpha: 1))
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Tag", style)], style: .body))
        ])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h),
                              visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
                              selection: [])

        let corner = pixel(at: 390, y: 55, width: w, buffer: buffer)
        #expect(corner.r == 255 && corner.g == 255 && corner.b == 255)
    }
}
