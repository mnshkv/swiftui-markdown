// Line preprocessing utilities for the Markdown parser.
// Internal helpers used by MarkdownParser.parse in a later task.

/// Splits `source` into lines on `\n`, `\r\n`, and `\r`, dropping terminators.
///
/// - A trailing newline does NOT produce a final empty line.
/// - Blank lines in the middle of the input are preserved.
/// - Empty input returns `[]`.
func splitIntoLines(_ source: String) -> [Substring] {
    if source.isEmpty { return [] }

    var lines: [Substring] = []
    var start = source.startIndex
    var i = source.startIndex

    while i < source.endIndex {
        let ch = source[i]
        // Swift treats `\r\n` (CRLF) as a single extended grapheme cluster,
        // so it shows up as one Character here — handle it first.
        if ch == "\r\n" {
            lines.append(source[start..<i])
            start = source.index(after: i)
            i = start
            continue
        } else if ch == "\n" || ch == "\r" {
            lines.append(source[start..<i])
            start = source.index(after: i)
            i = start
            continue
        }
        i = source.index(after: i)
    }

    // Trailing content without a terminator (no final empty line for trailing newline).
    if start < source.endIndex {
        lines.append(source[start..<i])
    }

    return lines
}

/// Expands each `\t` in `line` to spaces so that the following character
/// lands on a column that is a multiple of `tabWidth` (4-column tab stops).
///
/// Examples (default `tabWidth = 4`):
/// - `"\t# H"` → `"    # H"` (tab at col 0 → 4 spaces)
/// - `"a\tb"`  → `"a   b"`  (tab after 1 char → 3 spaces, next stop col 4)
/// - `"ab\tcd"` → `"ab  cd"` (tab after 2 chars → 2 spaces, next stop col 4)
func expandTabs(_ line: Substring, tabWidth: Int = 4) -> String {
    guard tabWidth > 0 else { return String(line) }

    var output = ""
    output.reserveCapacity(line.count)
    var column = 0

    for ch in line {
        if ch == "\t" {
            let spaces = tabWidth - (column % tabWidth)
            output.append(String(repeating: " ", count: spaces))
            column += spaces
        } else {
            output.append(ch)
            column += 1
        }
    }

    return output
}