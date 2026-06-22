// Container/indentation helpers for the Markdown parser.
// Internal parse-time helpers used by the dispatcher (later task) to gate
// lazy continuation (K3) and paragraph interruption (M4).
//
// Note: tabs are expanded upstream by `expandTabs` before these helpers run,
// so `stripUpTo3Spaces` only handles space characters — it does NOT attempt to
// handle tabs.

/// Drops 0–3 leading spaces from `line`. If `line` has 4 or more leading
/// spaces, returns it unchanged so that an indented-code block remains
/// detectable.
///
/// - `"   # H"` (3 spaces) → `"# H"`
/// - `"    code"` (4 spaces) → `"    code"` (kept)
/// - `""` → `""`
func stripUpTo3Spaces(_ line: Substring) -> Substring {
    var leading = 0
    for ch in line {
        if ch == " " { leading += 1 } else { break }
    }
    return leading >= 4 ? line : line.drop(while: { $0 == " " })
}

/// Returns true if `line` begins a block construct that can interrupt or
/// convert an open paragraph (K3 gating). Single-line detectable only:
/// ATX heading, setext underline (`===`/`---`), fenced code, thematic break,
/// blockquote (`>`), or a minimal list-marker peek. Returns false for table,
/// link-ref-def, footnote-def (handled by their own parsers in later tasks),
/// indented code (≥4 leading spaces), and plain text.
func isBlockStart(_ line: Substring) -> Bool {
    let s = stripUpTo3Spaces(line)
    guard !s.isEmpty else { return false }
    let first = s.first!

    // ATX heading: 1–6 `#` chars.
    if first == "#" { return true }

    // Blockquote.
    if first == ">" { return true }

    // Fenced code or thematic break or list marker all begin with one of
    // `` ` ``, `~`, `-`, `*`, `+`. Setext underline begins with `=` or `-`.
    if first == "`" || first == "~" {
        return isFence(s, open: first)
    }
    if first == "=" {
        return isSetextUnderline(s, ch: "=")
    }
    if first == "-" {
        // Could be thematic break, setext underline (`---`), fence? no, or list marker.
        if isThematicBreak(s) { return true }
        if isSetextUnderline(s, ch: "-") { return true }
        // Minimal marker peek for interruption classification; full recognizer is T18.
        return isListMarkerPeek(s)
    }
    if first == "*" || first == "+" {
        if isThematicBreak(s) { return true }
        // Minimal marker peek for interruption classification; full recognizer is T18.
        return isListMarkerPeek(s)
    }
    // Underscore-led thematic break (e.g. `___`, `_ _ _`). Underscore is not
    // a list marker, so the only construct to check is thematic break.
    if first == "_" {
        return isThematicBreak(s)
    }

    // Ordered list marker: digit run.
    if first.isNumber && first.isASCII {
        // Minimal marker peek for interruption classification; full recognizer is T18.
        return isListMarkerPeek(s)
    }

    return false
}

/// Returns true if `line` can interrupt an open paragraph. Per CommonMark:
/// ATX heading, thematic break, blockquote, fenced code, unordered list
/// (non-empty item), and ordered list with start number 1 (non-empty item)
/// interrupt. Setext underline does NOT interrupt here (it converts the
/// pending paragraph into a heading — handled by the dispatcher, not by
/// interruption). Indented code (≥4 leading spaces) does not interrupt.
func canInterruptParagraph(_ line: Substring) -> Bool {
    let s = stripUpTo3Spaces(line)
    guard !s.isEmpty else { return false }
    let first = s.first!

    // ATX heading.
    if first == "#" { return true }

    // Blockquote.
    if first == ">" { return true }

    // Fenced code.
    if first == "`" || first == "~" {
        return isFence(s, open: first)
    }

    // Thematic break (but NOT setext `---`, which would be caught here too —
    // thematic break requires the line to be only `-`,`*`,`_` + spaces).
    if first == "-" || first == "*" || first == "_" {
        if isThematicBreak(s) { return true }
    }
    // `*` could be a list marker; `-` could be a list marker.
    if first == "-" || first == "*" || first == "+" {
        // Minimal marker peek for interruption classification; full recognizer is T18.
        return isUnorderedListNonEmptyItem(s)
    }

    // Ordered list: only start number 1 with non-empty item interrupts.
    if first.isNumber && first.isASCII {
        return isOrderedListStartOneNonEmpty(s)
    }

    // Setext `===` does not interrupt.
    return false
}

// MARK: - Single-construct classifiers (private)

private func isFence(_ s: Substring, open: Character) -> Bool {
    // A fence is a run of ≥3 identical `open` chars, optionally followed by
    // an info string. Here we only need to know it begins with ≥3.
    var count = 0
    for ch in s {
        if ch == open { count += 1 } else { break }
    }
    return count >= 3
}

private func isSetextUnderline(_ s: Substring, ch: Character) -> Bool {
    // A setext underline is a line of `=` or `-` (possibly with trailing
    // whitespace). It must contain only that char (and spaces).
    for c in s {
        if c != ch && c != " " { return false }
    }
    // Must have at least one of `ch`.
    return s.contains(ch)
}

func isThematicBreak(_ s: Substring) -> Bool {
    // Thematic break: line containing only `-`, `*`, `_` and spaces, with at
    // least three of one of those markers.
    var dash = 0, star = 0, underscore = 0
    for c in s {
        switch c {
        case "-": dash += 1
        case "*": star += 1
        case "_": underscore += 1
        case " ": continue
        default: return false
        }
    }
    return dash >= 3 || star >= 3 || underscore >= 3
}

// MARK: - Minimal list-marker peek (T18 supersedes later)
//
// Minimal marker peek for interruption classification; full recognizer is T18.
// These helpers only answer "is this a list marker (with non-empty content)?"
// and "is the ordered start number exactly 1?" — enough for isBlockStart /
// canInterruptParagraph. Do NOT reuse for actual list parsing.

private func isListMarkerPeek(_ s: Substring) -> Bool {
    // True for any valid unordered or ordered marker (regardless of number),
    // followed by a space or end-of-line. Used by isBlockStart.
    guard let first = s.first else { return false }
    if first == "-" || first == "*" || first == "+" {
        return isUnorderedListNonEmptyItem(s) || isUnorderedListEmptyItem(s)
    }
    if first.isNumber && first.isASCII {
        return isOrderedMarkerAny(s)
    }
    return false
}

private func isUnorderedListNonEmptyItem(_ s: Substring) -> Bool {
    guard let first = s.first else { return false }
    guard first == "-" || first == "*" || first == "+" else { return false }
    // Marker is the single char; next must be space or end-of-line.
    var i = s.startIndex
    i = s.index(after: i)
    if i == s.endIndex {
        // Marker alone, no content — empty item.
        return false
    }
    let after = s[i]
    guard after == " " || after == "\t" else { return false }
    // Skip whitespace after marker; require non-whitespace content remaining.
    let rest = s[i...].drop(while: { $0 == " " || $0 == "\t" })
    return !rest.isEmpty
}

private func isUnorderedListEmptyItem(_ s: Substring) -> Bool {
    guard let first = s.first else { return false }
    guard first == "-" || first == "*" || first == "+" else { return false }
    var i = s.index(after: s.startIndex)
    if i == s.endIndex { return true }
    let after = s[i]
    guard after == " " || after == "\t" else { return false }
    let rest = s[i...].drop(while: { $0 == " " || $0 == "\t" })
    return rest.isEmpty
}

private func isOrderedMarkerAny(_ s: Substring) -> Bool {
    // One or more ASCII digits, then `.` or `)`, then space or end-of-line.
    var i = s.startIndex
    var digits = 0
    while i < s.endIndex && s[i].isNumber && s[i].isASCII {
        digits += 1
        i = s.index(after: i)
    }
    guard digits > 0, i < s.endIndex else { return false }
    let punct = s[i]
    guard punct == "." || punct == ")" else { return false }
    i = s.index(after: i)
    if i == s.endIndex { return true }
    let after = s[i]
    return after == " " || after == "\t"
}

private func isOrderedListStartOneNonEmpty(_ s: Substring) -> Bool {
    // Digit run must be exactly "1", then `.` or `)`, then space, then
    // non-whitespace content.
    var i = s.startIndex
    var digits = ""
    while i < s.endIndex && s[i].isNumber && s[i].isASCII {
        digits.append(s[i])
        i = s.index(after: i)
    }
    guard digits == "1", i < s.endIndex else { return false }
    let punct = s[i]
    guard punct == "." || punct == ")" else { return false }
    i = s.index(after: i)
    if i == s.endIndex { return false }
    let after = s[i]
    guard after == " " || after == "\t" else { return false }
    let rest = s[i...].drop(while: { $0 == " " || $0 == "\t" })
    return !rest.isEmpty
}
