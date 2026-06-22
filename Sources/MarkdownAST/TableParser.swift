// GFM table row splitting and delimiter validation (Pass A helpers).
//
// These helpers are `internal` — used by `BlockParser` to recognise GFM
// tables (Wave 3, T13). Pass B / Task 25 resolves the raw cell strings into
// parsed inlines.
//
// Pure Swift, no Foundation: all scanning is manual character iteration.

/// Split a GFM table row into cells.
///
/// Rules (GFM §4.6 + task spec):
/// - Split on `|`, but a `\` immediately followed by `|` is a literal pipe
///   (NOT a split point); after splitting, the `\` is removed so the cell
///   contains a literal `|`.
/// - Other `\x` sequences are kept LITERAL (the `\` stays) for the inline
///   pass (Task 25) to resolve.
/// - One optional leading `|` and one optional trailing `|` are stripped
///   (they are delimiters, not cell content).
/// - Each resulting cell is trimmed of leading/trailing whitespace.
///
/// Examples:
/// - `| a | b |` → `["a", "b"]`
/// - `a | b`     → `["a", "b"]`
/// - `| a \| b |` → `["a | b"]`   (the `\|` unescaped to a literal `|`)
/// - `| a \* b |` → `["a \* b"]`  (the `\*` kept literal for the inline pass)
func splitTableRow(_ line: String) -> [String] {
    // First pass: walk the string, building a buffer of chars while tracking
    // `\` escapes. Unescaped `|` becomes a split boundary; `\|` becomes a
    // literal `|` in the buffer (the `\` is dropped); any other `\x` keeps
    // both chars in the buffer.
    var cells: [String] = []
    var buf: [Character] = []
    var escaped = false
    for ch in line {
        if escaped {
            if ch == "|" {
                // `\|` → literal pipe in the cell (drop the backslash).
                buf.append("|")
            } else {
                // Other `\x` → keep both chars literal for the inline pass.
                buf.append("\\")
                buf.append(ch)
            }
            escaped = false
        } else if ch == "\\" {
            // Start escape; the next char decides what happens.
            escaped = true
        } else if ch == "|" {
            cells.append(String(buf))
            buf.removeAll(keepingCapacity: true)
        } else {
            buf.append(ch)
        }
    }
    // A trailing dangling `\` (no following char) is kept literal.
    if escaped { buf.append("\\") }
    // The final cell: anything after the last unescaped `|`. If the line had
    // a trailing `|` delimiter, `buf` is empty here and we append an empty
    // cell — which we then strip below as the optional trailing delimiter.
    cells.append(String(buf))

    // Strip ONE optional leading and ONE optional trailing empty cell that
    // arise from delimiting pipes (`| a | b |` splits to `["", "a", "b", ""]`).
    // An empty cell at the edge from genuine empty content (`| | b |`) is
    // indistinguishable here, but GFM treats a leading/trailing `|` as purely
    // delimiting, so stripping one on each side matches the spec.
    if cells.count >= 2, cells.first == "" { cells.removeFirst() }
    if cells.count >= 1, cells.last == "" { cells.removeLast() }

    // Trim leading/trailing whitespace of each cell.
    return cells.map { trimCellWhitespace($0) }
}

/// Validate a GFM table delimiter row and return the per-column alignments.
///
/// Rules:
/// - Split the row into cells via `splitTableRow` (so `\|` in a delimiter is
///   a literal pipe — unusual but consistent).
/// - The whole row (raw, before splitting) must contain ONLY `|`, `-`, `:`,
///   and whitespace. Any other character ⇒ reject (return nil).
/// - Each trimmed cell must match `:?-+:?` (optional `:`, one or more `-`,
///   optional `:`). Empty cells or cells with other chars ⇒ reject.
/// - Map each cell to its alignment: leading `:` only → `.left`; trailing
///   `:` only → `.right`; both `:` → `.center`; neither `:` → `.none`.
func delimiterAlignments(_ line: String) -> [MarkdownTable.Alignment]? {
    // Safety reject: the raw row must only contain `|`, `-`, `:`, whitespace.
    for ch in line {
        if ch == "|" || ch == "-" || ch == ":" || ch.isWhitespace { continue }
        return nil
    }

    let cells = splitTableRow(line)
    if cells.isEmpty { return nil }

    var alignments: [MarkdownTable.Alignment] = []
    alignments.reserveCapacity(cells.count)
    for cell in cells {
        // Each cell must match `:?-+:?`.
        var idx = cell.startIndex
        let end = cell.endIndex

        // Optional leading `:`.
        let hasLeadingColon = idx < end && cell[idx] == ":"
        if hasLeadingColon { idx = cell.index(after: idx) }

        // One or more `-`.
        var dashes = 0
        while idx < end, cell[idx] == "-" {
            dashes += 1
            idx = cell.index(after: idx)
        }
        guard dashes >= 1 else { return nil }

        // Optional trailing `:`.
        let hasTrailingColon = idx < end && cell[idx] == ":"
        if hasTrailingColon { idx = cell.index(after: idx) }

        // Nothing else may follow.
        guard idx == end else { return nil }

        switch (hasLeadingColon, hasTrailingColon) {
        case (true, true): alignments.append(.center)
        case (true, false): alignments.append(.left)
        case (false, true): alignments.append(.right)
        case (false, false): alignments.append(.none)
        }
    }
    return alignments
}

/// Trim leading/trailing whitespace without Foundation.
private func trimCellWhitespace(_ s: String) -> String {
    var sub = Substring(s)
    while let f = sub.first, f.isWhitespace { sub = sub.dropFirst() }
    while let l = sub.last, l.isWhitespace { sub = sub.dropLast() }
    return String(sub)
}
