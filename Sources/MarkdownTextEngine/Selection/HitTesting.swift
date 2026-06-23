import CoreText
import CoreGraphics

// MARK: - Hit-testing

/// Returns the `TextPosition` in the document's flattened UTF-16 index space
/// that corresponds to the given point in the document's coordinate space.
///
/// - If `point.y` is above all text blocks, returns position 0.
/// - If `point.y` is below all text blocks, returns the end position.
/// - For non-text (rule, image, list, …) blocks: they are skipped for y-containment
///   but their UTF-16 base contribution (always 0 length + 1 separator) is still counted.
public func position(at point: CGPoint, in layout: DocumentLayout, doc: TextDocument) -> TextPosition {
    // 1. Compute per-block UTF-16 bases
    let bases = utf16Bases(for: doc)
    let flattened = flattenedText(doc)
    let totalUTF16 = flattened.utf16.count

    // 2. Collect text blocks with their indices
    let textBlocks: [(blockIndex: Int, rect: CGRect, lines: [LineFrame])] = layout.blocks.enumerated().compactMap {
        if case .text(let rect, let lines) = $0.element {
            return ($0.offset, rect, lines)
        }
        return nil
    }

    guard !textBlocks.isEmpty else {
        return TextPosition(index: 0)
    }

    // 3. Find which text block the point falls into (y-based).
    // Track whether we snapped to the first or last block for edge-case handling.
    enum BlockSnap { case exact, snapFirst, snapLast }
    let targetBlock: (blockIndex: Int, rect: CGRect, lines: [LineFrame])
    let blockSnap: BlockSnap
    if let found = textBlocks.first(where: { $0.rect.minY <= point.y && point.y < $0.rect.maxY }) {
        targetBlock = found
        blockSnap = .exact
    } else if point.y < textBlocks[0].rect.minY {
        // Above all text → snap to first text block start
        targetBlock = textBlocks[0]
        blockSnap = .snapFirst
    } else {
        // Below all text → snap to last text block end
        targetBlock = textBlocks[textBlocks.count - 1]
        blockSnap = .snapLast
    }

    let blockBase = bases[targetBlock.blockIndex]
    let lines = targetBlock.lines

    guard !lines.isEmpty else {
        return TextPosition(index: blockBase)
    }

    // 4. Find the line within the block, with snap direction awareness.
    enum LineSnap { case exact, snapFirst, snapLast }
    let targetLine: LineFrame
    let lineSnap: LineSnap
    if blockSnap == .snapFirst {
        // Point is above the entire document → position 0
        return TextPosition(index: 0)
    } else if blockSnap == .snapLast {
        // Point is below the entire document → end position
        return TextPosition(index: totalUTF16)
    } else if let found = lines.first(where: { $0.origin.y <= point.y && point.y < $0.origin.y + $0.size.height }) {
        targetLine = found
        lineSnap = .exact
    } else if point.y < lines[0].origin.y {
        targetLine = lines[0]
        lineSnap = .snapFirst
    } else {
        targetLine = lines[lines.count - 1]
        lineSnap = .snapLast
    }

    // 5. If we snapped to the start of the first line, return line start; for last line snap, return line end.
    if lineSnap == .snapFirst {
        let globalIndex = blockBase + targetLine.charRange.lowerBound
        return TextPosition(index: max(0, min(globalIndex, totalUTF16)))
    } else if lineSnap == .snapLast {
        let globalIndex = blockBase + targetLine.charRange.upperBound
        return TextPosition(index: max(0, min(globalIndex, totalUTF16)))
    }

    // 6. Use CTLine to get local UTF-16 index within the paragraph's attributed string.
    let localX = point.x - targetLine.origin.x
    let localPoint = CGPoint(x: localX, y: 0)
    let localIndex = CTLineGetStringIndexForPosition(targetLine.ctLine, localPoint)

    // localIndex is already the UTF-16 offset within the paragraph's attributed string.
    let globalIndex = blockBase + localIndex

    // 7. Clamp
    let clamped = max(0, min(globalIndex, totalUTF16))
    return TextPosition(index: clamped)
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
