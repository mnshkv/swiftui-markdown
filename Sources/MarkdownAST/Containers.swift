// Container/indentation helpers for the Markdown parser.
// Internal parse-time helpers used by the dispatcher (later task) to gate
// lazy continuation (K3) and paragraph interruption (M4).
//
// Note: tabs are expanded upstream by `expandTabs` before these helpers run,
// so `stripUpTo3Spaces` only handles space characters — it does NOT attempt to
// handle tabs.

/// Drops 0–3 leading spaces from `line`; lines with 4+ leading spaces are
/// returned unchanged so indented-code blocks remain detectable.
func stripUpTo3Spaces(_ line: Substring) -> Substring {
    var leading = 0
    for ch in line {
        if ch == " " { leading += 1 } else { break }
    }
    return leading >= 4 ? line : line.drop(while: { $0 == " " })
}

/// True if `line` begins a single-line-detectable block construct (ATX/setext
/// heading, fence, thematic break, blockquote, or list marker) for K3 gating.
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

/// True if `line` can interrupt an open paragraph per CommonMark (ATX heading,
/// thematic break, blockquote, fence, or a non-empty list item; setext does not).
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

/// True if `s` begins a code fence: a run of at least three identical `open`
/// characters (any trailing info string is irrelevant here).
private func isFence(_ s: Substring, open: Character) -> Bool {
    var count = 0
    for ch in s {
        if ch == open { count += 1 } else { break }
    }
    return count >= 3
}

/// True if `s` is a setext underline: only the char `ch` (`=` or `-`) and
/// spaces, with at least one `ch`.
private func isSetextUnderline(_ s: Substring, ch: Character) -> Bool {
    for c in s {
        if c != ch && c != " " { return false }
    }
    // Must have at least one of `ch`.
    return s.contains(ch)
}

/// True if `s` is a thematic break: only `-`, `*`, `_` and spaces, with at
/// least three of a single marker char.
func isThematicBreak(_ s: Substring) -> Bool {
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

/// True if `s` starts with any valid unordered or ordered list marker
/// (regardless of start number); used by `isBlockStart` for interruption checks.
private func isListMarkerPeek(_ s: Substring) -> Bool {
    guard let first = s.first else { return false }
    if first == "-" || first == "*" || first == "+" {
        return isUnorderedListNonEmptyItem(s) || isUnorderedListEmptyItem(s)
    }
    if first.isNumber && first.isASCII {
        return isOrderedMarkerAny(s)
    }
    return false
}

/// True if `s` is an unordered marker (`-`/`*`/`+`) followed by a space/tab and
/// at least one non-whitespace content character.
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

/// True if `s` is an unordered marker (`-`/`*`/`+`) alone or followed only by
/// whitespace (an empty list item).
private func isUnorderedListEmptyItem(_ s: Substring) -> Bool {
    guard let first = s.first else { return false }
    guard first == "-" || first == "*" || first == "+" else { return false }
    let i = s.index(after: s.startIndex)
    if i == s.endIndex { return true }
    let after = s[i]
    guard after == " " || after == "\t" else { return false }
    let rest = s[i...].drop(while: { $0 == " " || $0 == "\t" })
    return rest.isEmpty
}

/// True if `s` is an ordered list marker: one or more ASCII digits, then `.`
/// or `)`, then a space or end-of-line (any start number).
private func isOrderedMarkerAny(_ s: Substring) -> Bool {
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

/// True if `s` is an ordered marker with start number `1` followed by
/// non-empty content — the only ordered list that may interrupt a paragraph.
private func isOrderedListStartOneNonEmpty(_ s: Substring) -> Bool {
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
