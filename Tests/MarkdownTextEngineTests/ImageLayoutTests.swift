import Testing
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("Block image layout (Task 6.1)")
struct ImageLayoutTests {

    // MARK: - Helpers

    private func makeDoc(_ attachment: ImageAttachment) -> TextDocument {
        TextDocument(blocks: [.image(attachment)])
    }

    private func makeDocWithParagraphThenImage(_ attachment: ImageAttachment) -> TextDocument {
        let style = TextStyle(fontSize: 17, color: .black)
        return TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Hello", style)], style: .body)),
            .image(attachment)
        ])
    }

    // MARK: 6.1.1 — Normal intrinsic size fits within width

    @Test("image smaller than width: rect width == intrinsicSize.width")
    func imageSmallerThanWidth() throws {
        let att = ImageAttachment(source: "img.png", intrinsicSize: CGSize(width: 100, height: 75), alt: "A")
        let doc = makeDoc(att)
        let layout = LayoutEngine.layout(doc, width: 400)
        guard case .image(let rect, _) = layout.blocks[0] else {
            Issue.record("expected .image block"); return
        }
        #expect(rect.width == 100)
        #expect(rect.height == 75)
        #expect(rect.width <= 400)
    }

    // MARK: 6.1.2 — Image wider than available width must be scaled down

    @Test("image wider than width: rect.width == available width, aspect ratio preserved")
    func imageWiderThanWidth() throws {
        let att = ImageAttachment(source: "big.png", intrinsicSize: CGSize(width: 800, height: 400), alt: "B")
        let doc = makeDoc(att)
        let layout = LayoutEngine.layout(doc, width: 400)
        guard case .image(let rect, _) = layout.blocks[0] else {
            Issue.record("expected .image block"); return
        }
        #expect(rect.width <= 400, "image must not exceed available width")
        // Aspect ratio: intrinsic is 2:1, so height should be half of width
        let expectedHeight = rect.width * (400.0 / 800.0)
        #expect(abs(rect.height - expectedHeight) < 1.0, "aspect ratio must be preserved")
    }

    // MARK: 6.1.3 — Zero intrinsicSize falls back to placeholder

    @Test("zero intrinsicSize uses placeholder size")
    func zeroIntrinsicSize() throws {
        let att = ImageAttachment(source: "unknown.png", intrinsicSize: .zero, alt: "C")
        let doc = makeDoc(att)
        let layout = LayoutEngine.layout(doc, width: 400)
        guard case .image(let rect, _) = layout.blocks[0] else {
            Issue.record("expected .image block"); return
        }
        #expect(rect.width > 0, "placeholder width must be positive")
        #expect(rect.height > 0, "placeholder height must be positive")
        #expect(rect.width <= 400, "placeholder must fit within available width")
    }

    // MARK: 6.1.4 — contentSize.height >= imageRect.maxY

    @Test("document ending in image: contentSize.height >= imageRect.maxY")
    func contentSizeCoversImage() throws {
        let att = ImageAttachment(source: "photo.jpg", intrinsicSize: CGSize(width: 200, height: 150), alt: "D")
        let doc = makeDoc(att)
        let layout = LayoutEngine.layout(doc, width: 400)
        guard case .image(let rect, _) = layout.blocks[0] else {
            Issue.record("expected .image block"); return
        }
        #expect(layout.contentSize.height >= rect.maxY, "contentSize.height must cover image maxY")
    }

    // MARK: 6.1.5 — Paragraph then image: image is below paragraph

    @Test("paragraph followed by image: image rect is below paragraph rect")
    func imageBelowParagraph() throws {
        let att = ImageAttachment(source: "after.png", intrinsicSize: CGSize(width: 100, height: 50), alt: "E")
        let doc = makeDocWithParagraphThenImage(att)
        let layout = LayoutEngine.layout(doc, width: 400)
        guard layout.blocks.count == 2 else {
            Issue.record("expected 2 blocks"); return
        }
        guard case .text(let paraRect, _) = layout.blocks[0] else {
            Issue.record("first block must be text"); return
        }
        guard case .image(let imgRect, _) = layout.blocks[1] else {
            Issue.record("second block must be image"); return
        }
        #expect(imgRect.minY >= paraRect.maxY, "image must appear below paragraph")
    }

    // MARK: 6.1.6 — Image rect.x is at origin.x (not offset)

    @Test("image rect starts at document x origin")
    func imageRectXOrigin() throws {
        let att = ImageAttachment(source: "img.png", intrinsicSize: CGSize(width: 100, height: 75), alt: "F")
        let doc = makeDoc(att)
        let layout = LayoutEngine.layout(doc, width: 400)
        guard case .image(let rect, _) = layout.blocks[0] else {
            Issue.record("expected .image block"); return
        }
        #expect(rect.origin.x == 0)
    }
}
