import Testing
import CoreGraphics
@testable import MarkdownTextEngine

// MARK: - Kitchen-sink mixed-document regression test
//
// Guards against cross-block-type index drift now that all block types coexist.
// The document contains, in order:
//   0. paragraph
//   1. list (2 items)
//   2. GFM table (header + 1 body row)
//   3. block image (with alt text)
//   4. quote (paragraph)
//   5. code block
//
// flattenedText joins block contributions with "\n":
//   "Hello world\nFirst\nSecond\nCol1\tCol2\nA\tB\nPhoto\nQuoted text\ncode here"
//
// utf16 block bases (all BMP, so utf16.count == unicodeScalars.count):
//   0: paragraph  base=0,  len=11  ("Hello world")
//   1: list       base=12, len=12  ("First\nSecond")
//   2: table      base=25, len=13  ("Col1\tCol2\nA\tB")  ← 4+1+4+1+1+1+1=13
//   3: image      base=39, len=5   ("Photo")
//   4: quote      base=45, len=11  ("Quoted text")
//   5: code       base=57, len=9   ("code here")
//   total = 66

@Suite("Mixed-document index-space consistency")
struct MixedDocumentTests {

    // MARK: - Fixture

    private func makeDoc() -> TextDocument {
        let s = TextStyle(fontSize: 14, color: .black)
        let bodyStyle = ParagraphStyle.body

        // 0. Paragraph
        let para = Block.paragraph(Paragraph(
            runs: [.text("Hello world", s)],
            style: bodyStyle
        ))

        // 1. List — 2 items, each a single-paragraph document
        let listItem1 = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("First", s)], style: bodyStyle))
        ])
        let listItem2 = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Second", s)], style: bodyStyle))
        ])
        let list = Block.list(List(marker: .bullet, isTight: true, items: [listItem1, listItem2]))

        // 2. Table — header ["Col1", "Col2"], one row ["A", "B"]
        let table = Block.table(Table(
            alignments: [.leading, .leading],
            header: [[.text("Col1", s)], [.text("Col2", s)]],
            rows: [[[.text("A", s)], [.text("B", s)]]],
            cellStyle: s
        ))

        // 3. Block image
        let image = Block.image(ImageAttachment(
            source: "test://photo.png",
            intrinsicSize: CGSize(width: 200, height: 100),
            alt: "Photo"
        ))

        // 4. Quote — single paragraph
        let quoteInner = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Quoted text", s)], style: bodyStyle))
        ])
        let quote = Block.quote(quoteInner)

        // 5. Code block
        let code = Block.codeBlock(CodeBlock(
            lines: ["code here"],
            language: nil,
            style: s
        ))

        return TextDocument(blocks: [para, list, table, image, quote, code])
    }

    // MARK: - Flattened text length

    @Test("flattenedText UTF-16 count matches per-block-walk expectation")
    func flattenedTextLength() {
        let doc = makeDoc()
        let flat = flattenedText(doc)
        let total = flat.utf16.count

        // Compute expected total from the per-block contributions joined by "\n".
        let blockTexts = doc.blocks.map { textForBlock($0) }
        let expectedTotal = blockTexts.map(\.utf16.count).reduce(0, +)
            + (blockTexts.count - 1)  // one "\n" separator between each pair of blocks

        #expect(total == expectedTotal,
                "flattenedText UTF-16 count (\(total)) should equal per-block walk (\(expectedTotal))")
    }

    // MARK: - Block base offsets

    @Test("utf16Bases for mixed doc match expected positions")
    func utf16BasesMatchExpected() {
        let doc = makeDoc()
        let bases = utf16Bases(for: doc)

        // Verify all 6 blocks get a base, in order.
        #expect(bases.count == 6)

        // Block 0: paragraph "Hello world" → base 0
        #expect(bases[0] == 0)

        // Block 1: list "First\nSecond" → base 12 (11 + 1 separator)
        #expect(bases[1] == 12)

        // Block 2: table "Col1\tCol2\nA\tB" → base 25 (12 + 12 + 1 separator)
        #expect(bases[2] == 25)

        // Block 3: image "Photo" → base 39 (25 + 13 + 1 separator)
        // Table text = "Col1\tCol2\nA\tB": 4+1+4+1+1+1+1 = 13 UTF-16 units
        #expect(bases[3] == 39)

        // Block 4: quote "Quoted text" → base 45 (39 + 5 + 1 separator)
        #expect(bases[4] == 45)

        // Block 5: code "code here" → base 57 (45 + 11 + 1 separator)
        #expect(bases[5] == 57)

        // Sanity: total length = 57 + 9 = 66
        let flat = flattenedText(doc)
        #expect(flat.utf16.count == 66)
    }

    // MARK: - Layout roundtrip: blocks laid out without crash

    @Test("layout of mixed document does not crash and produces 6 block frames")
    func layoutDoesNotCrash() {
        let doc = makeDoc()
        let layout = LayoutEngine.layout(doc, width: 400)
        #expect(layout.blocks.count == 6,
                "Expected 6 block frames, got \(layout.blocks.count)")
        #expect(layout.contentSize.height > 0,
                "Content height should be positive")
    }

    // MARK: - copyText spanning list → table → quote

    @Test("copyText across list + table + quote returns expected substring")
    func copyTextCrossBlock() {
        let doc = makeDoc()
        // Start: offset 18 = first character of "Second" (block 1, local offset 6).
        // Flat: "Hello world\nFirst\nSecond\nCol1\tCol2\nA\tB\nPhoto\nQuoted text\ncode here"
        //        0         11 12   17 18    24 25         38 39 40   45 46
        // Verify positions using the flattened string directly.
        let flat = flattenedText(doc)
        let utf16 = flat.utf16

        // flat (66 UTF-16 units):
        //   "Hello world\nFirst\nSecond\nCol1\tCol2\nA\tB\nPhoto\nQuoted text\ncode here"
        //    0         11 12   17 18    24 25       37 38 39  43 44 45          56 57
        //
        // Block bases (reconfirmed from utf16BasesMatchExpected):
        //   0: paragraph  base=0
        //   1: list       base=12  ("First\nSecond", len=12)
        //   2: table      base=25  ("Col1\tCol2\nA\tB", len=13)
        //   3: image      base=39  ("Photo", len=5)
        //   4: quote      base=45  ("Quoted text", len=11)
        //   5: code       base=57  ("code here", len=9)
        //
        // Cross-block selection: from offset 18 (start of "Second" in the list)
        // through offset 51 (end of "Quoted", i.e. base 45 + 6 chars = 51, exclusive).
        // Expected: "Second\nCol1\tCol2\nA\tB\nPhoto\nQuoted"
        let startIdx = 18  // 'S' of "Second"
        let endIdx = 51    // exclusive end, just after 'd' of "Quoted"

        // Verify the start character is 'S'
        let startUTF16 = utf16.index(utf16.startIndex, offsetBy: startIdx)
        let startChar = String(utf16[startUTF16..<utf16.index(startUTF16, offsetBy: 1)])
        #expect(startChar == "S", "Start of range should be 'S' (start of 'Second'); got '\(startChar)'")

        // Verify the end-1 character is 'd' (last char of "Quoted")
        let endMinus1 = utf16.index(utf16.startIndex, offsetBy: endIdx - 1)
        let endChar = String(utf16[endMinus1..<utf16.index(endMinus1, offsetBy: 1)])
        #expect(endChar == "d", "Char before end should be 'd' (end of 'Quoted'); got '\(endChar)'")

        // copyText
        let range = TextRange(
            start: TextPosition(index: startIdx),
            end: TextPosition(index: endIdx)
        )
        let copied = copyText(for: range, doc: doc)

        // Build expected directly from flattenedText to ensure consistency.
        let flatStartIdx = utf16.index(utf16.startIndex, offsetBy: startIdx)
        let flatEndIdx = utf16.index(utf16.startIndex, offsetBy: endIdx)
        let expectedFromFlat = String(utf16[flatStartIdx..<flatEndIdx]) ?? ""

        #expect(copied == expectedFromFlat,
                "copyText mismatch: got '\(copied)', expected '\(expectedFromFlat)'")

        // Also assert the literal value as a regression anchor.
        #expect(copied == "Second\nCol1\tCol2\nA\tB\nPhoto\nQuoted",
                "copyText should return 'Second\\nCol1\\tCol2\\nA\\tB\\nPhoto\\nQuoted'")
    }
}
