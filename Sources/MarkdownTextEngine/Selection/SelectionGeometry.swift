import CoreText
import CoreGraphics

// MARK: - Selection rects

/// Returns an array of `CGRect`s that visually cover the given `range` within the layout.
///
/// Only `.text` block frames contribute rects. Rects are in the document's coordinate space.
/// An empty (zero-length) range returns an empty array.
///
/// CONSISTENCY CONTRACT: this function recurses into `.list` and `.quote` blocks using the
/// same text-flattening order as `textForBlock` / `flattenedText`. Specifically:
/// - For `.list`: items are visited in order; between items there is a 1-unit "\n" separator.
/// - For `.quote`: the inner document is visited with its own `flattenedText` — which is
///   itself built from `textForBlock` with inter-block "\n" separators.
public func selectionRects(for range: TextRange, in layout: DocumentLayout, doc: TextDocument) -> [CGRect] {
    guard range.start.index < range.end.index else { return [] }

    let bases = utf16Bases(for: doc)
    var result: [CGRect] = []

    for (blockIndex, blockFrame) in layout.blocks.enumerated() {
        guard blockIndex < bases.count else { continue }
        let blockBase = bases[blockIndex]

        switch blockFrame {
        case .text(_, let lines):
            let blockLen = blockUTF16Length(doc.blocks[blockIndex])
            let blockStart = blockBase
            let blockEnd = blockBase + blockLen
            if range.end.index <= blockStart || range.start.index >= blockEnd { continue }

            for line in lines {
                let lineGlobalStart = blockBase + line.charRange.lowerBound
                let lineGlobalEnd = blockBase + line.charRange.upperBound
                if range.end.index <= lineGlobalStart || range.start.index >= lineGlobalEnd { continue }

                let selStart = max(range.start.index, lineGlobalStart)
                let selEnd = min(range.end.index, lineGlobalEnd)
                let localStart = selStart - blockBase
                let localEnd = selEnd - blockBase

                let startX = CTLineGetOffsetForStringIndex(line.ctLine, localStart, nil)
                let endX = CTLineGetOffsetForStringIndex(line.ctLine, localEnd, nil)
                let minX = min(startX, endX)
                let width = abs(endX - startX)
                guard width > 0 else { continue }

                result.append(CGRect(
                    x: line.origin.x + minX,
                    y: line.origin.y,
                    width: width,
                    height: line.size.height
                ))
            }

        case .list(_, let itemLayouts, _, _):
            guard case .list(let listBlock) = doc.blocks[blockIndex] else { continue }
            let listLen = blockUTF16Length(doc.blocks[blockIndex])
            let listStart = blockBase
            let listEnd = blockBase + listLen
            if range.end.index <= listStart || range.start.index >= listEnd { continue }

            // Walk items: each item's text is flattenedText(item), joined by "\n".
            // CONSISTENCY CONTRACT: same order and separator as textForBlock(.list).
            var itemCursor = blockBase
            for (i, itemLayout) in itemLayouts.enumerated() {
                guard i < listBlock.items.count else { break }
                let itemDoc = listBlock.items[i]
                let itemText = flattenedText(itemDoc)
                let itemLen = itemText.utf16.count
                let itemStart = itemCursor
                let itemEnd = itemCursor + itemLen

                if range.start.index < itemEnd && range.end.index > itemStart {
                    // Clamp range into this item's sub-space
                    let clampedRange = TextRange(
                        start: TextPosition(index: max(range.start.index, itemStart)),
                        end: TextPosition(index: min(range.end.index, itemEnd))
                    )
                    // Build a shifted range: subtract itemStart to get local offsets within this item
                    let localRange = TextRange(
                        start: TextPosition(index: clampedRange.start.index - itemStart),
                        end: TextPosition(index: clampedRange.end.index - itemStart)
                    )
                    result += selectionRects(for: localRange, in: itemLayout, doc: itemDoc)
                }

                // Advance past this item and the "\n" separator (if not last)
                itemCursor += itemLen
                if i < itemLayouts.count - 1 {
                    itemCursor += 1  // separator "\n"
                }
            }

        case .quote(_, let innerLayout, _):
            guard case .quote(let innerDoc) = doc.blocks[blockIndex] else { continue }
            let quoteLen = blockUTF16Length(doc.blocks[blockIndex])
            let quoteStart = blockBase
            let quoteEnd = blockBase + quoteLen
            if range.end.index <= quoteStart || range.start.index >= quoteEnd { continue }

            // Clamp range into the inner document's text space.
            // CONSISTENCY CONTRACT: quote text = flattenedText(innerDoc), so offset
            // from quoteStart directly maps into the inner document's UTF-16 space.
            let localRange = TextRange(
                start: TextPosition(index: max(range.start.index, quoteStart) - quoteStart),
                end: TextPosition(index: min(range.end.index, quoteEnd) - quoteStart)
            )
            result += selectionRects(for: localRange, in: innerLayout, doc: innerDoc)

        case .rule, .image, .table, .code:
            continue
        }
    }

    return result
}
