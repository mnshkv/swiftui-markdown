import Testing
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("Image orientation")
struct ImageOrientationTests {
    // Regression: a block image must render upright, not vertically mirrored.
    // The renderer draws into a y-flipped context, and CGContextDrawImage assumes
    // a y-up space, so without compensation images come out upside-down.
    @Test("block image renders upright, not vertically mirrored")
    func blockImageUpright() {
        let side = 30
        // Build an image with RED at the top (high CG-y) and BLUE at the bottom.
        guard let ic = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                 bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            Issue.record("no image context"); return
        }
        ic.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ic.fill(CGRect(x: 0, y: 0, width: side, height: side / 2))          // blue, low y
        ic.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ic.fill(CGRect(x: 0, y: side / 2, width: side, height: side / 2))   // red, high y
        guard let img = ic.makeImage() else { Issue.record("no image"); return }

        let attach = ImageAttachment(source: "f", intrinsicSize: CGSize(width: side, height: side), alt: "")
        let layout = LayoutEngine.layout(TextDocument(blocks: [.image(attach)]), width: CGFloat(side))
        guard case .image(let rect, _) = layout.blocks.first else { Issue.record("no image block"); return }
        let outH = Int(layout.contentSize.height.rounded(.up)) + 2
        guard let (ctx, buf) = makeWhiteContext(width: side, height: outH) else { Issue.record("no ctx"); return }
        defer { buf.deallocate() }
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(outH),
                              visible: CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(outH)),
                              selection: [], images: ["f": img])

        // Red was at the top of the source image, so it must appear at the top of
        // the rendered output; blue at the bottom. (Mirrored output would swap them.)
        let top = pixel(at: side / 2, y: Int(rect.minY) + 4, width: side, buffer: buf)
        let bottom = pixel(at: side / 2, y: Int(rect.maxY) - 4, width: side, buffer: buf)
        #expect(top.r > top.b, "top of image should be red; got (\(top.r),\(top.g),\(top.b))")
        #expect(bottom.b > bottom.r, "bottom of image should be blue; got (\(bottom.r),\(bottom.g),\(bottom.b))")
    }
}
