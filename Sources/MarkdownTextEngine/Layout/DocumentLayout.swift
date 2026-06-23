import CoreText
import CoreGraphics

/// A positioned line within a paragraph block.
public struct LineFrame {
    /// Top-left origin of the line in the document's coordinate space.
    public var origin: CGPoint
    /// Width × height of the line's bounding box.
    public var size: CGSize
    /// CoreText ascent (above baseline).
    public var ascent: CGFloat
    /// CoreText descent (below baseline, positive value).
    public var descent: CGFloat
    /// The underlying CoreText line.
    public var ctLine: CTLine
    /// UTF-16 code-unit range within the paragraph's flattened attributed string,
    /// matching the offsets produced by `CTTypesetterSuggestLineBreak` / `CFRange`.
    /// Wave 2's position-index space must be built in UTF-16 units to align with these values.
    /// Do NOT interpret these as Swift `Character` (extended grapheme cluster) indices.
    public var charRange: Range<Int>

    public init(origin: CGPoint, size: CGSize, ascent: CGFloat, descent: CGFloat,
                ctLine: CTLine, charRange: Range<Int>) {
        self.origin = origin; self.size = size
        self.ascent = ascent; self.descent = descent
        self.ctLine = ctLine; self.charRange = charRange
    }
}

/// A laid-out block within the document.
public enum BlockFrame {
    case text(rect: CGRect, lines: [LineFrame])
    case rule(CGRect)
    case image(rect: CGRect, attachment: ImageAttachment)
    /// A laid-out list block.
    /// - `itemLayouts`: one `DocumentLayout` per list item (recursive layout in item-indent space).
    /// - `markerFrames`: one `CGRect` per item — the bounding box of the marker glyph.
    /// - `markerStrings`: the marker label string for each item (e.g. "•" or "3.").
    /// - `rect`: bounding rect of the entire list block in document space.
    case list(rect: CGRect, itemLayouts: [DocumentLayout], markerFrames: [CGRect], markerStrings: [String])
    /// A laid-out block-quote.
    /// - `inner`: the recursive layout of the quoted document.
    /// - `barRect`: the thin left-edge bar rect (document space).
    /// - `rect`: bounding rect of the entire quote block.
    case quote(rect: CGRect, inner: DocumentLayout, barRect: CGRect)
    /// A laid-out GFM table.
    /// - `rect`: bounding rect of the entire table in document space.
    /// - `columnX`: absolute x-coordinate of the left edge of each column (in document space).
    /// - `rowYs`: absolute y-coordinates of each row boundary; count = numRows + 1.
    ///   rowYs[i] is the top of row i; rowYs[numRows] is the bottom of the last row.
    ///   Row 0 is the header, rows 1..N are body rows.
    /// - `cellLines`: row-major cell layout; cellLines[row][col] is [LineFrame] for that cell.
    /// - `borders`: grid border rects (horizontal row dividers + vertical column dividers).
    case table(rect: CGRect, columnX: [CGFloat], rowYs: [CGFloat],
               cellLines: [[[LineFrame]]], borders: [CGRect])

    /// A laid-out fenced/indented code block.
    /// - `rect`: bounding rect of the entire block in document space.
    /// - `box`: the padded background box rect (slightly inset inside `rect`).
    /// - `lines`: laid-out monospace LineFrames (one or more per source line due to wrapping).
    /// - `languageLabel`: optional LineFrame for the language tag drawn above the box.
    case code(rect: CGRect, box: CGRect, lines: [LineFrame], languageLabel: LineFrame?)
}

/// The complete layout result for a `TextDocument`.
public struct DocumentLayout {
    public var blocks: [BlockFrame]
    public var contentSize: CGSize

    public init(blocks: [BlockFrame], contentSize: CGSize) {
        self.blocks = blocks; self.contentSize = contentSize
    }

    /// Returns the indices of blocks whose bounding rect intersects `visible`.
    /// Used for windowed draw culling and for testing that off-screen blocks are skipped.
    public func visibleBlockIndices(in visible: CGRect) -> [Int] {
        blocks.enumerated().compactMap { (i, block) in
            blockRect(block).intersects(visible) ? i : nil
        }
    }

    /// Returns the bounding rect of a `BlockFrame` in document space.
    public func blockRect(_ frame: BlockFrame) -> CGRect {
        switch frame {
        case .text(let rect, _): return rect
        case .rule(let rect): return rect
        case .image(let rect, _): return rect
        case .list(let rect, _, _, _): return rect
        case .quote(let rect, _, _): return rect
        case .table(let rect, _, _, _, _): return rect
        case .code(let rect, _, _, _): return rect
        }
    }
}
