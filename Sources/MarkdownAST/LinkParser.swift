// Link/image parsing helpers (Wave 8+): balanced bracket/paren matching and
// destination/title parsing. Pure functions over character arrays.

/// Index of the `]` that closes the `[` at `openAt`, honoring nesting,
/// backslash escapes, and code-span opacity, or nil if unbalanced.
func matchBracket(_ chars: [Character], openAt: Int) -> Int? {
    matchDelimiters(chars, openAt: openAt, open: "[", close: "]")
}

/// Index of the `)` that closes the `(` at `openAt` (same rules as
/// `matchBracket`), or nil if unbalanced.
func matchParen(_ chars: [Character], openAt: Int) -> Int? {
    matchDelimiters(chars, openAt: openAt, open: "(", close: ")")
}

/// Balanced-delimiter scan: counts `open`/`close` depth, skipping `\`-escaped
/// characters and treating backtick code spans as opaque.
private func matchDelimiters(_ chars: [Character], openAt: Int, open: Character, close: Character) -> Int? {
    guard openAt < chars.count, chars[openAt] == open else { return nil }
    var depth = 0
    var i = openAt
    while i < chars.count {
        let c = chars[i]
        if c == "\\" {
            i += 2 // skip the escaped character
            continue
        }
        if c == "`" {
            var n = 0
            while i + n < chars.count, chars[i + n] == "`" { n += 1 }
            if let close = closingBacktickRun(chars, from: i + n, length: n) {
                i = close + n // jump past an opaque code span
            } else {
                i += n // unmatched run — treat the backticks as literal
            }
            continue
        }
        if c == open {
            depth += 1
        } else if c == close {
            depth -= 1
            if depth == 0 { return i }
        }
        i += 1
    }
    return nil
}

/// Splits the inside of a link's `(...)` into destination and optional title.
/// Handles `<dest>` (spaces allowed), a bare dest with balanced parens,
/// `"…"`/`'…'`/`(…)` titles, and backslash escapes in both. Returns nil if
/// malformed — an unterminated angle dest/title, a non-title token where a title
/// is expected, or any non-whitespace left over after the title.
func splitDestinationAndTitle(_ s: String) -> (dest: String, title: String?)? {
    let chars = Array(s)
    var i = 0
    func skipWhitespace() { while i < chars.count, chars[i].isWhitespace { i += 1 } }

    skipWhitespace()
    var dest = ""
    if i < chars.count, chars[i] == "<" {
        i += 1
        while i < chars.count, chars[i] != ">" {
            if chars[i] == "\\", i + 1 < chars.count {
                dest.append(chars[i + 1]); i += 2; continue
            }
            if chars[i] == "\n" || chars[i] == "<" { return nil }
            dest.append(chars[i]); i += 1
        }
        guard i < chars.count, chars[i] == ">" else { return nil }
        i += 1
    } else {
        var depth = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count { dest.append(chars[i + 1]); i += 2; continue }
            if c.isWhitespace { break }
            if c == "(" { depth += 1 } else if c == ")" {
                if depth == 0 { break }
                depth -= 1
            }
            dest.append(c); i += 1
        }
    }

    skipWhitespace()
    var title: String?
    if i < chars.count {
        let opener = chars[i]
        let closer: Character
        switch opener {
        case "\"": closer = "\""
        case "'": closer = "'"
        case "(": closer = ")"
        default: return nil // a non-title token after the destination ⇒ malformed
        }
        i += 1
        var body = ""
        var closed = false
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count { body.append(chars[i + 1]); i += 2; continue }
            if chars[i] == closer { closed = true; i += 1; break }
            body.append(chars[i]); i += 1
        }
        guard closed else { return nil }
        title = body
    }

    skipWhitespace()
    guard i >= chars.count else { return nil } // leftover junk
    return (dest, title)
}

/// Index of a closing backtick run of exactly `n` backticks at or after `start`
/// (runs of other lengths are content), or nil.
func closingBacktickRun(_ chars: [Character], from start: Int, length n: Int) -> Int? {
    var j = start
    while j < chars.count {
        guard chars[j] == "`" else { j += 1; continue }
        var m = 0
        while j + m < chars.count, chars[j + m] == "`" { m += 1 }
        if m == n { return j }
        j += m
    }
    return nil
}
