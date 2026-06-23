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
            result += textBlockRects(for: range, lines: lines, blockBase: blockBase,
                                     blockLen: blockUTF16Length(doc.blocks[blockIndex]))

        case .list(_, let itemLayouts, _, _):
            guard case .list(let listBlock) = doc.blocks[blockIndex] else { continue }
            result += listBlockRects(for: range, itemLayouts: itemLayouts, listBlock: listBlock,
                                     blockBase: blockBase,
                                     blockLen: blockUTF16Length(doc.blocks[blockIndex]))

        case .quote(_, let innerLayout, _):
            guard case .quote(let innerDoc) = doc.blocks[blockIndex] else { continue }
            result += quoteBlockRects(for: range, innerLayout: innerLayout, innerDoc: innerDoc,
                                      blockBase: blockBase,
                                      blockLen: blockUTF16Length(doc.blocks[blockIndex]))

        case .table(_, _, _, let cellLines, _):
            guard blockIndex < doc.blocks.count,
                  case .table(let tableBlock) = doc.blocks[blockIndex] else { continue }
            result += tableBlockRects(for: range, cellLines: cellLines, tableBlock: tableBlock,
                                      blockBase: blockBase,
                                      blockLen: blockUTF16Length(doc.blocks[blockIndex]))

        case .code(_, _, let codeLines, _):
            guard blockIndex < doc.blocks.count,
                  case .codeBlock(let cb) = doc.blocks[blockIndex] else { continue }
            result += codeBlockRects(for: range, codeLines: codeLines, codeBlock: cb,
                                     blockBase: blockBase,
                                     blockLen: blockUTF16Length(doc.blocks[blockIndex]))

        case .rule:
            continue

        case .image(let rect, _):
            // BLOCK IMAGE ATOMIC SELECTION:
            // The block contributes `alt.utf16.count` UTF-16 units (see textForBlock(.image)).
            // If the selection range overlaps the image's span, the entire image rect is
            // returned as a single selection rect (atomic: selecting any part highlights all).
            let imageLen = blockUTF16Length(doc.blocks[blockIndex])
            let imageStart = blockBase
            let imageEnd = blockBase + imageLen
            // Only contribute a rect if the image has content (alt is non-empty) and
            // the selection touches it.
            if imageLen > 0 && range.start.index < imageEnd && range.end.index > imageStart {
                result.append(rect)
            }
        }
    }

    return result
}

// MARK: - Per-block-type rect helpers
// Each helper mirrors exactly the corresponding case body from the original selectionRects
// implementation. The extraction is purely mechanical: same arithmetic, same order, same
// separator counting. Do not change the logic without also updating textForBlock / flattenedText.

/// Rects for a `.text` block frame (paragraph / heading / etc.).
private func textBlockRects(
    for range: TextRange,
    lines: [LineFrame],
    blockBase: Int,
    blockLen: Int
) -> [CGRect] {
    let blockStart = blockBase
    let blockEnd = blockBase + blockLen
    guard range.end.index > blockStart && range.start.index < blockEnd else { return [] }

    var result: [CGRect] = []
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
    return result
}

/// Rects for a `.list` block frame.
///
/// CONSISTENCY CONTRACT: items are visited in order; between items there is a 1-unit "\n"
/// separator — same as textForBlock(.list).
private func listBlockRects(
    for range: TextRange,
    itemLayouts: [DocumentLayout],
    listBlock: List,
    blockBase: Int,
    blockLen: Int
) -> [CGRect] {
    let listStart = blockBase
    let listEnd = blockBase + blockLen
    guard range.end.index > listStart && range.start.index < listEnd else { return [] }

    var result: [CGRect] = []
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
    return result
}

/// Rects for a `.quote` block frame.
///
/// CONSISTENCY CONTRACT: quote text = flattenedText(innerDoc), so offset from quoteStart
/// directly maps into the inner document's UTF-16 space — same as textForBlock(.quote).
private func quoteBlockRects(
    for range: TextRange,
    innerLayout: DocumentLayout,
    innerDoc: TextDocument,
    blockBase: Int,
    blockLen: Int
) -> [CGRect] {
    let quoteStart = blockBase
    let quoteEnd = blockBase + blockLen
    guard range.end.index > quoteStart && range.start.index < quoteEnd else { return [] }

    // Clamp range into the inner document's text space.
    let localRange = TextRange(
        start: TextPosition(index: max(range.start.index, quoteStart) - quoteStart),
        end: TextPosition(index: min(range.end.index, quoteEnd) - quoteStart)
    )
    return selectionRects(for: localRange, in: innerLayout, doc: innerDoc)
}

/// Rects for a `.table` block frame.
///
/// CONSISTENCY CONTRACT: matches textForBlock(.table).
/// Row order: [header, body row 0, ...]. Cells joined by "\t", rows by "\n".
private func tableBlockRects(
    for range: TextRange,
    cellLines: [[[LineFrame]]],
    tableBlock: Table,
    blockBase: Int,
    blockLen: Int
) -> [CGRect] {
    let tableStart = blockBase
    let tableEnd = blockBase + blockLen
    guard range.end.index > tableStart && range.start.index < tableEnd else { return [] }

    var result: [CGRect] = []
    var allRows: [[[InlineRun]]] = [tableBlock.header]
    allRows.append(contentsOf: tableBlock.rows)

    var rowCursor = blockBase
    for (rowIdx, row) in allRows.enumerated() {
        let rowCellLines = rowIdx < cellLines.count ? cellLines[rowIdx] : []

        var cellCursor = rowCursor
        for (colIdx, cellRunGroup) in row.enumerated() {
            let cellText = textForRuns(cellRunGroup)
            let cellLen = cellText.utf16.count
            let cellStart = cellCursor
            let cellEnd = cellCursor + cellLen

            if range.start.index < cellEnd && range.end.index > cellStart {
                let colFrames = colIdx < rowCellLines.count ? rowCellLines[colIdx] : []
                for line in colFrames {
                    let lineGlobalStart = cellStart + line.charRange.lowerBound
                    let lineGlobalEnd = cellStart + line.charRange.upperBound
                    if range.end.index <= lineGlobalStart || range.start.index >= lineGlobalEnd { continue }

                    let selStart = max(range.start.index, lineGlobalStart)
                    let selEnd = min(range.end.index, lineGlobalEnd)
                    let localStart = selStart - cellStart
                    let localEnd = selEnd - cellStart

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
            }

            cellCursor += cellLen
            if colIdx < row.count - 1 {
                cellCursor += 1  // separator "\t"
            }
        }

        let rowText = row.map { textForRuns($0) }.joined(separator: "\t")
        rowCursor += rowText.utf16.count
        if rowIdx < allRows.count - 1 {
            rowCursor += 1  // separator "\n"
        }
    }
    return result
}

/// Rects for a `.code` block frame.
///
/// CONSISTENCY CONTRACT: matches textForBlock(.codeBlock). Source lines joined by "\n".
private func codeBlockRects(
    for range: TextRange,
    codeLines: [LineFrame],
    codeBlock: CodeBlock,
    blockBase: Int,
    blockLen: Int
) -> [CGRect] {
    let codeStart = blockBase
    let codeEnd = blockBase + blockLen
    guard range.end.index > codeStart && range.start.index < codeEnd else { return [] }

    var result: [CGRect] = []

    // Build per-source-line base offsets.
    var sourceLineBases: [Int] = []
    var lineBaseCursor = codeStart
    for (i, srcLine) in codeBlock.lines.enumerated() {
        sourceLineBases.append(lineBaseCursor)
        lineBaseCursor += srcLine.utf16.count
        if i < codeBlock.lines.count - 1 {
            lineBaseCursor += 1  // separator "\n"
        }
    }

    // Walk code line frames in order, mapping them to source lines.
    var frameIdx = 0
    for (srcIdx, srcLine) in codeBlock.lines.enumerated() {
        let srcLen = srcLine.utf16.count
        let srcBase = sourceLineBases[srcIdx]

        var framesForLine: [LineFrame] = []
        while frameIdx < codeLines.count {
            let frame = codeLines[frameIdx]
            let localEnd = frame.charRange.upperBound
            if localEnd <= srcLen || (srcLen == 0 && frame.charRange.isEmpty) {
                framesForLine.append(frame)
                frameIdx += 1
                if localEnd >= srcLen { break }
            } else {
                break
            }
        }

        for line in framesForLine {
            let lineGlobalStart = srcBase + line.charRange.lowerBound
            let lineGlobalEnd = srcBase + line.charRange.upperBound
            if range.end.index <= lineGlobalStart || range.start.index >= lineGlobalEnd { continue }

            let selStart = max(range.start.index, lineGlobalStart)
            let selEnd = min(range.end.index, lineGlobalEnd)
            let localStart = selStart - srcBase
            let localEnd = selEnd - srcBase

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
    }
    return result
}
