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
    case list(rect: CGRect, items: [[BlockFrame]])
    case quote(rect: CGRect, inner: [BlockFrame])
    case table(rect: CGRect)
    case code(rect: CGRect)
}

/// The complete layout result for a `TextDocument`.
public struct DocumentLayout {
    public var blocks: [BlockFrame]
    public var contentSize: CGSize

    public init(blocks: [BlockFrame], contentSize: CGSize) {
        self.blocks = blocks; self.contentSize = contentSize
    }
}
