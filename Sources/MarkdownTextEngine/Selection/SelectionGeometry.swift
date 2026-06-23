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

        case .table(_, _, _, let cellLines, _):
            guard blockIndex < doc.blocks.count,
                  case .table(let tableBlock) = doc.blocks[blockIndex] else { continue }

            let tableLen = blockUTF16Length(doc.blocks[blockIndex])
            let tableStart = blockBase
            let tableEnd = blockBase + tableLen
            if range.end.index <= tableStart || range.start.index >= tableEnd { continue }

            // CONSISTENCY CONTRACT: matches textForBlock(.table).
            // Row order: [header, body row 0, ...]. Cells joined by "\t", rows by "\n".
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

        case .code(_, _, let codeLines, _):
            guard blockIndex < doc.blocks.count,
                  case .codeBlock(let cb) = doc.blocks[blockIndex] else { continue }

            let codeLen = blockUTF16Length(doc.blocks[blockIndex])
            let codeStart = blockBase
            let codeEnd = blockBase + codeLen
            if range.end.index <= codeStart || range.start.index >= codeEnd { continue }

            // CONSISTENCY CONTRACT: matches textForBlock(.codeBlock).
            // Source lines joined by "\n".
            var sourceLineBases: [Int] = []
            var lineBaseCursor = codeStart
            for (i, srcLine) in cb.lines.enumerated() {
                sourceLineBases.append(lineBaseCursor)
                lineBaseCursor += srcLine.utf16.count
                if i < cb.lines.count - 1 {
                    lineBaseCursor += 1  // separator "\n"
                }
            }

            // Walk code line frames in order, mapping them to source lines
            var frameIdx = 0
            for (srcIdx, srcLine) in cb.lines.enumerated() {
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

        case .rule, .image:
            continue
        }
    }

    return result
}
