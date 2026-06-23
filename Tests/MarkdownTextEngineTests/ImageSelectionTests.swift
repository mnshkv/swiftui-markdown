import Testing
import CoreGraphics
import CoreText
@testable import MarkdownTextEngine

// MARK: - Helpers

private let textStyle = TextStyle(fontSize: 17, color: .black)

/// Creates a document with [paragraph("Before"), block image, paragraph("After")].
private func makeDocAroundImage(alt: String, intrinsicSize: CGSize = CGSize(width: 200, height: 150))
    -> TextDocument
{
    let att = ImageAttachment(source: "img.png", intrinsicSize: intrinsicSize, alt: alt)
    return TextDocument(blocks: [
        .paragraph(Paragraph(runs: [.text("Before", textStyle)], style: .body)),
        .image(att),
        .paragraph(Paragraph(runs: [.text("After", textStyle)], style: .body))
    ])
}

@Suite("Image in selection (Task 6.4)")
struct ImageSelectionTests {

    // MARK: 6.4.1 — textForBlock(.image) returns alt text

    @Test("textForBlock(.image) returns attachment.alt")
    func textForBlockImageIsAlt() {
        let att = ImageAttachment(source: "img.png", intrinsicSize: CGSize(width: 100, height: 100), alt: "My Photo")
        let block = Block.image(att)
        #expect(textForBlock(block) == "My Photo")
    }

    // MARK: 6.4.2 — flattenedText includes alt text for block image

    @Test("flattenedText includes alt text for block image")
    func flattenedTextIncludesAlt() {
        let doc = makeDocAroundImage(alt: "TestAlt")
        let flat = flattenedText(doc)
        // Expected: "Before\nTestAlt\nAfter"
        #expect(flat == "Before\nTestAlt\nAfter",
                "flattenedText must include alt text for block image (got: \(flat.debugDescription))")
    }

    // MARK: 6.4.3 — UTF-16 bases are consistent (paragraph after image has correct base offset)

    @Test("paragraph after image has correct UTF-16 base offset")
    func paragraphAfterImageBaseOffset() {
        let alt = "Photo"
        let doc = makeDocAroundImage(alt: alt)
        let flat = flattenedText(doc)
        // "Before" = 6, "\n" = 1, "Photo" = 5, "\n" = 1, "After" = 5 → total = 18
        // "After" starts at index 13
        let expectedBase = "Before".utf16.count + 1 + alt.utf16.count + 1
        let bases = utf16Bases(for: doc)
        // bases[2] = base of third block = paragraph "After"
        #expect(bases.count == 3)
        #expect(bases[2] == expectedBase,
                "paragraph after image must start at UTF-16 offset \(expectedBase) (got \(bases[2]))")
    }

    // MARK: 6.4.4 — selectionRects covering a block image returns the image rect atomically

    @Test("selection range covering block image returns image rect atomically")
    func selectionRectForBlockImage() {
        let alt = "A Photo"
        let doc = makeDocAroundImage(alt: alt)
        let layout = LayoutEngine.layout(doc, width: 400)

        // Image is block index 1; alt = "A Photo" (7 UTF-16 units)
        // bases[1] = "Before".utf16.count + 1 = 7
        let imgBase = "Before".utf16.count + 1
        let imgLen = alt.utf16.count  // 7

        // Select exactly the image's alt span
        let range = TextRange(
            start: TextPosition(index: imgBase),
            end: TextPosition(index: imgBase + imgLen)
        )
        let rects = selectionRects(for: range, in: layout, doc: doc)

        // Must return exactly 1 rect (the image rect), atomically
        #expect(rects.count == 1, "expected exactly 1 rect for image selection (got \(rects.count))")
        guard let rect = rects.first else { return }

        // The rect must match the image block's layout rect
        guard case .image(let imgRect, _) = layout.blocks[1] else {
            Issue.record("block 1 must be .image"); return
        }
        #expect(rect == imgRect, "selection rect must equal the image's layout rect")
    }

    // MARK: 6.4.5 — copyText for image selection returns alt text

    @Test("copyText for selection covering block image returns alt text")
    func copyTextForBlockImageReturnsAlt() {
        let alt = "Sky Photo"
        let doc = makeDocAroundImage(alt: alt)

        let imgBase = "Before".utf16.count + 1
        let imgLen = alt.utf16.count

        let range = TextRange(
            start: TextPosition(index: imgBase),
            end: TextPosition(index: imgBase + imgLen)
        )
        let text = copyText(for: range, doc: doc)
        #expect(text == alt, "copyText must return alt text for image selection (got: \(text.debugDescription))")
    }

    // MARK: 6.4.6 — partial overlap with image still returns image rect atomically

    @Test("partial selection overlap with block image returns image rect atomically")
    func partialOverlapReturnsImageRect() {
        let alt = "Banner"
        let doc = makeDocAroundImage(alt: alt)
        let layout = LayoutEngine.layout(doc, width: 400)

        // Select from inside "Before" through the first char of the image's alt
        let beforeEnd = "Before".utf16.count
        let imgBase = beforeEnd + 1
        let range = TextRange(
            start: TextPosition(index: beforeEnd - 2),   // inside "Before"
            end: TextPosition(index: imgBase + 1)         // 1 char into image alt
        )
        let rects = selectionRects(for: range, in: layout, doc: doc)

        // Must include the image rect
        guard case .image(let imgRect, _) = layout.blocks[1] else {
            Issue.record("block 1 must be .image"); return
        }
        #expect(rects.contains(imgRect),
                "partial overlap with image must include full image rect atomically")
    }

    // MARK: 6.4.7 — paragraph after image selects correctly (index bases consistent)

    @Test("paragraph after image selects correctly")
    func paragraphAfterImageSelects() {
        let alt = "Icon"
        let doc = makeDocAroundImage(alt: alt)
        let layout = LayoutEngine.layout(doc, width: 400)

        // "After" starts at bases[2]
        let afterBase = "Before".utf16.count + 1 + alt.utf16.count + 1
        let afterLen = "After".utf16.count

        let range = TextRange(
            start: TextPosition(index: afterBase),
            end: TextPosition(index: afterBase + afterLen)
        )
        let rects = selectionRects(for: range, in: layout, doc: doc)

        #expect(!rects.isEmpty, "paragraph after image must produce selection rects")
        // Must not include image rect
        guard case .image(let imgRect, _) = layout.blocks[1] else {
            Issue.record("block 1 must be .image"); return
        }
        #expect(!rects.contains(imgRect),
                "selection of post-image paragraph must not include image rect")
    }

    // MARK: 6.4.8 — empty alt block image contributes 0 UTF-16 units and yields no selection rect

    @Test("block image with empty alt contributes 0 UTF-16 units and yields no selection rect")
    func emptyAltImageNoRect() {
        let att = ImageAttachment(source: "icon.png", intrinsicSize: CGSize(width: 50, height: 50), alt: "")
        let doc = TextDocument(blocks: [.image(att)])
        let layout = LayoutEngine.layout(doc, width: 400)

        // With empty alt, flattenedText = ""
        #expect(flattenedText(doc) == "", "empty alt means flattenedText is empty")

        // Selection of any range should yield no rects (imageLen == 0)
        let range = TextRange(start: TextPosition(index: 0), end: TextPosition(index: 1))
        let rects = selectionRects(for: range, in: layout, doc: doc)
        #expect(rects.isEmpty, "empty alt image must yield no selection rect")
    }
}
