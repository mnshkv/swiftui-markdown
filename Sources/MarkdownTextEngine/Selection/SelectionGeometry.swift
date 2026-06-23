import CoreText
import CoreGraphics

// MARK: - Selection rects

/// Returns an array of `CGRect`s that visually cover the given `range` within the layout.
///
/// Only `.text` block frames contribute rects. Rects are in the document's coordinate space.
/// An empty (zero-length) range returns an empty array.
public func selectionRects(for range: TextRange, in layout: DocumentLayout, doc: TextDocument) -> [CGRect] {
    guard range.start.index < range.end.index else { return [] }

    let bases = utf16Bases(for: doc)
    var result: [CGRect] = []

    for (blockIndex, blockFrame) in layout.blocks.enumerated() {
        guard case .text(_, let lines) = blockFrame else { continue }
        guard blockIndex < bases.count else { continue }

        let blockBase = bases[blockIndex]
        // Length of this block in UTF-16 units
        let blockLen: Int
        if blockIndex + 1 < bases.count {
            // Next base minus separator
            let nextBase = bases[blockIndex + 1]
            // The separator between blocks is 1 UTF-16 unit,
            // so blockLen = nextBase - blockBase - 1
            blockLen = max(0, nextBase - blockBase - 1)
        } else {
            // Last block — compute directly
            let flattened = flattenedText(doc)
            blockLen = flattened.utf16.count - blockBase
        }

        // Does the range overlap this block?
        let blockStart = blockBase
        let blockEnd = blockBase + blockLen
        if range.end.index <= blockStart || range.start.index >= blockEnd { continue }

        // Walk lines within this block
        for line in lines {
            // Absolute UTF-16 range of this line within the document
            let lineGlobalStart = blockBase + line.charRange.lowerBound
            let lineGlobalEnd = blockBase + line.charRange.upperBound

            // Does the selection range overlap this line?
            if range.end.index <= lineGlobalStart || range.start.index >= lineGlobalEnd { continue }

            // Clamp selection to this line's range
            let selStart = max(range.start.index, lineGlobalStart)
            let selEnd = min(range.end.index, lineGlobalEnd)

            // Convert to local (within paragraph attributed string) indices
            let localStart = selStart - blockBase
            let localEnd = selEnd - blockBase

            // Get x-offsets from CoreText
            let startX = CTLineGetOffsetForStringIndex(line.ctLine, localStart, nil)
            let endX = CTLineGetOffsetForStringIndex(line.ctLine, localEnd, nil)

            let minX = min(startX, endX)
            let width = abs(endX - startX)
            guard width > 0 else { continue }

            let rect = CGRect(
                x: line.origin.x + minX,
                y: line.origin.y,
                width: width,
                height: line.size.height
            )
            result.append(rect)
        }
    }

    return result
}
