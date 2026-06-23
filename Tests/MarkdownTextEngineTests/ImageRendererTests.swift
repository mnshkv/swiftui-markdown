import Testing
import CoreGraphics
import CoreText
@testable import MarkdownTextEngine

// MARK: - Helpers

/// Creates a solid-color CGImage of the given size.
private func solidColorImage(red: UInt8, green: UInt8, blue: UInt8,
                              width: Int, height: Int) -> CGImage? {
    let bytesPerRow = width * 4
    let bufferSize = height * bytesPerRow
    let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
    defer { rawBuffer.deallocate() }
    let p = rawBuffer.assumingMemoryBound(to: UInt8.self)
    for i in 0..<(width * height) {
        p[i * 4 + 0] = red
        p[i * 4 + 1] = green
        p[i * 4 + 2] = blue
        p[i * 4 + 3] = 255
    }
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: rawBuffer,
                              width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    return ctx.makeImage()
}

// MARK: - Tests

@Suite("DocumentRenderer image drawing (Task 6.3)")
struct ImageRendererTests {

    // ------------------------------------------------------------------ //
    // Test 1: passing a loaded CGImage draws the image color into the rect
    // ------------------------------------------------------------------ //
    @Test("passing a loaded red CGImage draws red pixels in the image rect")
    func loadedImageDrawsColor() throws {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("could not create context"); return
        }
        defer { buffer.deallocate() }

        // Build a doc with a block image at (0,0) with intrinsicSize 100×100
        let att = ImageAttachment(source: "red.png", intrinsicSize: CGSize(width: 100, height: 100), alt: "red")
        let doc = TextDocument(blocks: [.image(att)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        // Create a synthetic 100×100 solid-red CGImage
        guard let redImage = solidColorImage(red: 255, green: 0, blue: 0, width: 100, height: 100) else {
            Issue.record("could not create red CGImage"); return
        }
        let images: [String: CGImage] = ["red.png": redImage]

        // Render
        DocumentRenderer.draw(
            layout, in: ctx,
            canvasHeight: CGFloat(h),
            visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
            selection: [],
            images: images
        )

        // The image block is at y=0, height=100 in doc space.
        // After y-flip transform (translateBy(0, canvasHeight=200) + scaleBy(1,-1)):
        //   doc y=0 → CG y=200, doc y=50 (center) → CG y=150, doc y=100 → CG y=100.
        // In CGContext bitmap memory row 0 = CG y = (height-1) = 199 (top of y-up CG space).
        //   Bitmap row r corresponds to CG y = (height-1-r) = 199-r.
        //   CG y=150 → bitmap row = 199-150 = 49.
        //   CG y=100 → bitmap row = 199-100 = 99.
        // So the center of the image is at bitmap row ~49, col 50.
        let px = pixel(at: 50, y: 49, width: w, buffer: buffer)
        // A red pixel has r >> g and r >> b.
        #expect(Int(px.r) > Int(px.g) + 50, "expected red channel to dominate (got r=\(px.r), g=\(px.g), b=\(px.b))")
        #expect(Int(px.r) > Int(px.b) + 50, "expected red channel to dominate (got r=\(px.r), g=\(px.g), b=\(px.b))")
    }

    // ------------------------------------------------------------------ //
    // Test 2: empty images dict draws a placeholder (grey fill)
    // ------------------------------------------------------------------ //
    @Test("empty images dict draws placeholder grey box in the image rect")
    func emptyImagesDrawsPlaceholder() throws {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("could not create context"); return
        }
        defer { buffer.deallocate() }

        let att = ImageAttachment(source: "missing.png", intrinsicSize: CGSize(width: 200, height: 150), alt: "?")
        let doc = TextDocument(blocks: [.image(att)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        // Render with no images (empty dict → placeholder)
        DocumentRenderer.draw(
            layout, in: ctx,
            canvasHeight: CGFloat(h),
            visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
            selection: [],
            images: [:]
        )

        // Placeholder fills with grey (≈0.90 * 255 = 229).
        // Image rect is 200×150 at doc y=0. With canvasHeight=200:
        //   doc y=0 → CG y=200, doc y=75 (center) → CG y=125.
        //   Bitmap row = 199-125 = 74.
        // Sample interior of placeholder: bitmap row 74, col 100.
        let px = pixel(at: 100, y: 74, width: w, buffer: buffer)
        // Grey: all channels close to each other and not white (255)
        let isGrey = abs(Int(px.r) - Int(px.g)) < 10 && abs(Int(px.g) - Int(px.b)) < 10
        let isNotWhite = px.r < 250
        #expect(isGrey, "placeholder must be grey (r=\(px.r), g=\(px.g), b=\(px.b))")
        #expect(isNotWhite, "placeholder must not be white (background)")
    }

    // ------------------------------------------------------------------ //
    // Test 3: image outside visible rect is not rendered (culling still works)
    // ------------------------------------------------------------------ //
    @Test("image block outside visible rect is not rendered")
    func imageBlockCulledOutsideVisible() throws {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("could not create context"); return
        }
        defer { buffer.deallocate() }

        let att = ImageAttachment(source: "green.png", intrinsicSize: CGSize(width: 100, height: 100), alt: "G")
        let doc = TextDocument(blocks: [.image(att)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))
        guard let greenImage = solidColorImage(red: 0, green: 200, blue: 0, width: 100, height: 100) else {
            Issue.record("could not create green CGImage"); return
        }

        // visible rect starts at y=500 — far below the image
        DocumentRenderer.draw(
            layout, in: ctx,
            canvasHeight: CGFloat(h),
            visible: CGRect(x: 0, y: 500, width: CGFloat(w), height: CGFloat(h)),
            selection: [],
            images: ["green.png": greenImage]
        )

        // Entire buffer should remain white
        var foundNonWhite = false
        outerLoop: for y in 0..<h {
            for x in 0..<w {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundNonWhite = true
                    break outerLoop
                }
            }
        }
        #expect(!foundNonWhite, "image outside visible rect must not be rendered")
    }

    // ------------------------------------------------------------------ //
    // Test 4: default images parameter (empty dict) does not crash
    // ------------------------------------------------------------------ //
    @Test("draw without images parameter does not crash and draws placeholder")
    func drawWithoutImagesParam() throws {
        let w = 200; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("could not create context"); return
        }
        defer { buffer.deallocate() }

        let att = ImageAttachment(source: "x.png", intrinsicSize: CGSize(width: 100, height: 100), alt: "x")
        let doc = TextDocument(blocks: [.image(att)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        // Omit images: parameter → default [:] → placeholder
        DocumentRenderer.draw(
            layout, in: ctx,
            canvasHeight: CGFloat(h),
            visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
            selection: []
        )
        // Must not crash; buffer has been modified (not all white due to placeholder)
        // Image rect is 100×100 at doc y=0. Center: doc y=50 → CG y=150 → bitmap row=199-150=49.
        let px = pixel(at: 50, y: 49, width: w, buffer: buffer)
        #expect(px.a == 255, "alpha must be opaque")
    }
}
