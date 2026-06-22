// List marker recognizer (CommonMark §5.1).
//
// Pure classifier: answers "does this line begin with a list marker?" and
// returns the marker geometry. It does NOT adjudicate thematic-break-vs-list
// precedence (a dispatcher concern — Task 19) and does NOT parse list items
// (Task 20). Tabs are already expanded to spaces upstream by `expandTabs`
// (Task 2), so this recognizer only handles space characters.
//
// Internal: consumed by the list parser / dispatcher in later tasks within
// the same module.

/// Result of recognizing a list marker at the start of a line.
///
/// `markerWidth` is measured from the marker start (not column 0); the
/// leading indent is recorded separately in `leadingIndent`. `contentStart`
/// is the absolute 0-based index where item content begins.
struct ListMarker: Equatable {
    /// `.bullet` for unordered, `.ordered(start:)` for ordered.
    var kind: MarkdownList.Kind
    /// 0–3 leading spaces before the marker (≥4 → indented code, not a list).
    var leadingIndent: Int
    /// Width from marker start, including the separator space(s). Capped so
    /// that ≥5 spaces after the marker count as 1 (the rest stay with content).
    var markerWidth: Int
    /// Integer start value of the digit run (ordered); 0 for unordered.
    var start: Int
    /// Bullet char (`-`/`+`/`*`) for unordered; nil for ordered.
    var bullet: Character?
    /// Delimiter (`.` or `)`) for ordered; nil for unordered.
    var orderedDelimiter: Character?
    /// Absolute 0-based index where item content begins = leadingIndent + markerWidth.
    var contentStart: Int
}

/// Recognizes a CommonMark §5.1 bullet or ordered list marker at the start of `line`.
/// Returns its geometry, or nil if no valid marker is present.
func listMarker(_ line: Substring) -> ListMarker? {
    var i = line.startIndex

    // Leading indent: 0–3 spaces. ≥4 → indented code block, not a list.
    var leadingIndent = 0
    while i < line.endIndex && line[i] == " " {
        leadingIndent += 1
        i = line.index(after: i)
    }
    if leadingIndent >= 4 { return nil }
    if i == line.endIndex { return nil }

    let first = line[i]

    // Bullet marker: `-`, `+`, or `*` followed by ≥1 space.
    if first == "-" || first == "+" || first == "*" {
        let markerLen = 1
        i = line.index(after: i)
        // Require ≥1 space after the bullet char.
        if i == line.endIndex || line[i] != " " { return nil }
        // Count spaces after the marker.
        var spacesAfter = 0
        while i < line.endIndex && line[i] == " " {
            spacesAfter += 1
            i = line.index(after: i)
        }
        let width = markerLen + (spacesAfter >= 5 ? 1 : spacesAfter)
        return ListMarker(
            kind: .bullet,
            leadingIndent: leadingIndent,
            markerWidth: width,
            start: 0,
            bullet: first,
            orderedDelimiter: nil,
            contentStart: leadingIndent + width
        )
    }

    // Ordered marker: 1–9 ASCII digits, then `.` or `)`, then ≥1 space.
    if first.isNumber && first.isASCII {
        var digits = 0
        var value = 0
        while i < line.endIndex && line[i].isNumber && line[i].isASCII {
            digits += 1
            if digits > 9 { return nil }
            value = value * 10 + Int(String(line[i]))!
            i = line.index(after: i)
        }
        guard digits >= 1, digits <= 9 else { return nil }
        guard i < line.endIndex else { return nil }
        let punct = line[i]
        guard punct == "." || punct == ")" else { return nil }
        i = line.index(after: i)
        // Require ≥1 space after the delimiter.
        if i == line.endIndex || line[i] != " " { return nil }
        var spacesAfter = 0
        while i < line.endIndex && line[i] == " " {
            spacesAfter += 1
            i = line.index(after: i)
        }
        let markerLen = digits + 1 // digit run + delimiter
        let width = markerLen + (spacesAfter >= 5 ? 1 : spacesAfter)
        return ListMarker(
            kind: .ordered(start: value),
            leadingIndent: leadingIndent,
            markerWidth: width,
            start: value,
            bullet: nil,
            orderedDelimiter: punct,
            contentStart: leadingIndent + width
        )
    }

    return nil
}
