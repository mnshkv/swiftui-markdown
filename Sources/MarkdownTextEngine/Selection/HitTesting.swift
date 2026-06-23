import CoreText
import CoreGraphics

// MARK: - Hit-testing

/// Returns the `TextPosition` in the document's flattened UTF-16 index space
/// that corresponds to the given point in the document's coordinate space.
///
/// - If `point.y` is above all text blocks (including nested), returns position 0.
/// - If `point.y` is below all text blocks, returns the end position.
/// - For non-text (rule, image, …) blocks: they are skipped for y-containment
///   but their UTF-16 base contribution is still counted.
///
/// CONSISTENCY CONTRACT: when recursing into list-item layouts and quote inner layouts,
/// the UTF-16 base offsets are computed using the same separator ("\n") and item order
/// as `textForBlock` / `flattenedText`. See `selectionRects` for the parallel implementation.
public func position(at point: CGPoint, in layout: DocumentLayout, doc: TextDocument) -> TextPosition {
    // Collect all "leaf text segments" in document order: each is a (globalUTF16Base, lines) pair.
    // We recurse into list items and quotes, computing absolute UTF-16 bases as we go.
    let flattened = flattenedText(doc)
    let totalUTF16 = flattened.utf16.count

    // Collect leaf segments
    var segments: [(utf16Base: Int, lines: [LineFrame])] = []
    collectTextSegments(
        blocks: layout.blocks,
        docBlocks: doc.blocks,
        utf16Bases: utf16Bases(for: doc),
        into: &segments
    )

    guard !segments.isEmpty else {
        return TextPosition(index: 0)
    }

    // 2. Find which segment the point falls into (y-based)
    enum BlockSnap { case exact, snapFirst, snapLast }
    let targetSegment: (utf16Base: Int, lines: [LineFrame])
    let blockSnap: BlockSnap

    if let found = segments.first(where: { seg in
        guard let first = seg.lines.first, let last = seg.lines.last else { return false }
        let top = first.origin.y
        let bottom = last.origin.y + last.size.height
        return top <= point.y && point.y < bottom
    }) {
        targetSegment = found
        blockSnap = .exact
    } else if point.y < (segments[0].lines.first?.origin.y ?? 0) {
        targetSegment = segments[0]
        blockSnap = .snapFirst
    } else {
        targetSegment = segments[segments.count - 1]
        blockSnap = .snapLast
    }

    let blockBase = targetSegment.utf16Base
    let lines = targetSegment.lines

    guard !lines.isEmpty else {
        return TextPosition(index: blockBase)
    }

    // 3. Handle snap to document edges
    if blockSnap == .snapFirst {
        return TextPosition(index: 0)
    } else if blockSnap == .snapLast {
        return TextPosition(index: totalUTF16)
    }

    // 4. Find the line within the segment
    enum LineSnap { case exact, snapFirst, snapLast }
    let targetLine: LineFrame
    let lineSnap: LineSnap

    if let found = lines.first(where: {
        $0.origin.y <= point.y && point.y < $0.origin.y + $0.size.height
    }) {
        targetLine = found
        lineSnap = .exact
    } else if point.y < lines[0].origin.y {
        targetLine = lines[0]
        lineSnap = .snapFirst
    } else {
        targetLine = lines[lines.count - 1]
        lineSnap = .snapLast
    }

    if lineSnap == .snapFirst {
        let globalIndex = blockBase + targetLine.charRange.lowerBound
        return TextPosition(index: max(0, min(globalIndex, totalUTF16)))
    } else if lineSnap == .snapLast {
        let globalIndex = blockBase + targetLine.charRange.upperBound
        return TextPosition(index: max(0, min(globalIndex, totalUTF16)))
    }

    // 5. Use CTLine to get local UTF-16 index within the paragraph's attributed string
    let localX = point.x - targetLine.origin.x
    let localPoint = CGPoint(x: localX, y: 0)
    let localIndex = CTLineGetStringIndexForPosition(targetLine.ctLine, localPoint)

    let globalIndex = blockBase + localIndex
    return TextPosition(index: max(0, min(globalIndex, totalUTF16)))
}

// MARK: - UTF-16 base computation

/// Returns an array of UTF-16 base offsets, one per block in `doc.blocks`.
///
/// Block `i` starts at UTF-16 offset `bases[i]` within `flattenedText(doc)`.
/// The separator `"\n"` between blocks contributes 1 UTF-16 unit.
func utf16Bases(for doc: TextDocument) -> [Int] {
    var bases: [Int] = []
    var cursor = 0
    for (i, block) in doc.blocks.enumerated() {
        bases.append(cursor)
        let blockText = blockUTF16Length(block)
        cursor += blockText
        if i < doc.blocks.count - 1 {
            cursor += 1  // separator "\n"
        }
    }
    return bases
}

/// Returns the UTF-16 length of the text contributed by a single block.
///
/// Delegates to `textForBlock` so there is a single source of truth for
/// inline-run flattening: `blockUTF16Length(b) == textForBlock(b).utf16.count`.
func blockUTF16Length(_ block: Block) -> Int {
    textForBlock(block).utf16.count
}

// MARK: - Recursive text segment collection

/// Collects all leaf text segments (`.text` blocks) from the layout tree,
/// computing their absolute UTF-16 bases in the same order as `textForBlock`.
///
/// CONSISTENCY CONTRACT:
/// - For `.list` blocks: items are visited in order; between items there is a
///   1-unit "\n" separator — matching `textForBlock(.list)`.
/// - For `.quote` blocks: the inner document is recursed with `utf16Bases(for: innerDoc)` —
///   matching `textForBlock(.quote)` which returns `flattenedText(innerDoc)`.
private func collectTextSegments(
    blocks: [BlockFrame],
    docBlocks: [Block],
    utf16Bases bases: [Int],
    into result: inout [(utf16Base: Int, lines: [LineFrame])]
) {
    for (blockIndex, blockFrame) in blocks.enumerated() {
        guard blockIndex < bases.count else { continue }
        let blockBase = bases[blockIndex]

        switch blockFrame {
        case .text(_, let lines):
            if !lines.isEmpty {
                result.append((utf16Base: blockBase, lines: lines))
            }

        case .list(_, let itemLayouts, _, _):
            guard blockIndex < docBlocks.count,
                  case .list(let listBlock) = docBlocks[blockIndex] else { continue }

            // CONSISTENCY CONTRACT: same order and separator as textForBlock(.list).
            var itemCursor = blockBase
            for (i, itemLayout) in itemLayouts.enumerated() {
                guard i < listBlock.items.count else { break }
                let itemDoc = listBlock.items[i]
                let itemText = flattenedText(itemDoc)
                let itemLen = itemText.utf16.count
                let itemBases = utf16Bases(for: itemDoc)

                // Build shifted bases for this item (absolute in the document)
                let shiftedBases = itemBases.map { itemCursor + $0 }
                collectTextSegments(
                    blocks: itemLayout.blocks,
                    docBlocks: itemDoc.blocks,
                    utf16Bases: shiftedBases,
                    into: &result
                )

                itemCursor += itemLen
                if i < itemLayouts.count - 1 {
                    itemCursor += 1  // separator "\n"
                }
            }

        case .quote(_, let innerLayout, _):
            guard blockIndex < docBlocks.count,
                  case .quote(let innerDoc) = docBlocks[blockIndex] else { continue }

            // CONSISTENCY CONTRACT: quote text == flattenedText(innerDoc).
            // Shift inner document bases by blockBase.
            let innerBases = utf16Bases(for: innerDoc)
            let shiftedBases = innerBases.map { blockBase + $0 }
            collectTextSegments(
                blocks: innerLayout.blocks,
                docBlocks: innerDoc.blocks,
                utf16Bases: shiftedBases,
                into: &result
            )

        case .rule, .image, .table, .code:
            continue
        }
    }
}
