import CoreGraphics

// MARK: - Link hit-test helper (Task 7.4)

/// Returns the `LinkPayload` and `TextRange` for the link run at `point`,
/// or `nil` if no link run exists at that point.
///
/// This is the pure seam extracted for unit testing of pressed-link highlight.
/// Touch-down / mouse-down wiring lives in `TextEngineView` (platform code).
///
/// Algorithm:
///   1. Hit-test `point` → `TextPosition`.
///   2. Walk the block at that position to find a `.link` run covering it.
///   3. Compute the `TextRange` for the entire link run and return it with the payload.
///
/// - Returns: `(payload: LinkPayload, range: TextRange)?` — `nil` when the
///   point doesn't land on any link.
public func linkRange(
    at point: CGPoint,
    layout: DocumentLayout,
    doc: TextDocument
) -> (payload: LinkPayload, range: TextRange)? {
    let pos = position(at: point, in: layout, doc: doc)
    let flat = flattenedText(doc)
    let total = flat.utf16.count
    let idx = max(0, min(pos.index, total))

    let bases = utf16Bases(for: doc)

    // Find the block containing this position.
    var blockIndex: Int? = nil
    for (i, base) in bases.enumerated() {
        let nextBase = (i + 1 < bases.count) ? bases[i + 1] : total + 1
        if idx >= base && idx < nextBase {
            blockIndex = i
            break
        }
    }
    guard let bi = blockIndex, bi < doc.blocks.count else { return nil }
    let block = doc.blocks[bi]
    guard case .paragraph(let para) = block else { return nil }

    let blockBase = bases[bi]
    let localOffset = idx - blockBase

    // Walk the inline runs to find the link covering localOffset,
    // computing the global TextRange as we go.
    return findLinkRange(at: localOffset, in: para.runs, globalBase: blockBase)
}

/// Recursively walks `runs` (starting at `cursorInRuns` = 0) to find a `.link` run
/// that contains `localOffset` (a UTF-16 offset within the paragraph's flattened text).
///
/// - Parameters:
///   - localOffset: UTF-16 offset within the runs' combined flattened text.
///   - runs: The inline runs to search.
///   - globalBase: The UTF-16 base of the start of `runs` within the whole document.
/// - Returns: The link payload and its global `TextRange`, or `nil`.
private func findLinkRange(
    at localOffset: Int,
    in runs: [InlineRun],
    globalBase: Int
) -> (payload: LinkPayload, range: TextRange)? {
    var cursor = 0
    for run in runs {
        switch run {
        case .text(let s, _):
            cursor += s.utf16.count

        case .link(let innerRuns, let payload):
            let innerText = textForRuns(innerRuns)
            let len = innerText.utf16.count
            if localOffset >= cursor && localOffset < cursor + len {
                // The hit falls inside this link run.
                let start = TextPosition(index: globalBase + cursor)
                let end   = TextPosition(index: globalBase + cursor + len)
                return (payload: payload, range: TextRange(start: start, end: end))
            }
            cursor += len

        case .inlineImage:
            cursor += 1  // U+FFFC placeholder

        case .lineBreak(let hard):
            cursor += (hard ? "\n" : "\u{2028}").utf16.count
        }
    }
    return nil
}
