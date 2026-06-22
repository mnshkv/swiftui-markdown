// Line preprocessing utilities for the Markdown parser.
// Internal helpers used by MarkdownParser.parse in a later task.

/// Splits `source` into lines on `\n`, `\r\n`, and `\r`, dropping terminators.
/// Returns the lines; empty input yields `[]` and a trailing newline adds no empty line.
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

/// Expands each `\t` in `line` to spaces, advancing to the next `tabWidth` tab stop.
/// Returns the expanded line as a `String`.
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
