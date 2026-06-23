// Inline parser (Pass B): resolves a raw leaf string into `[MarkdownInline]`.
//
// At this wave: plain text + backslash escapes only. Code spans, emphasis,
// links, autolinks, etc. are added by later tasks. Pass B owns all inline
// calls — `BlockParser` does no inline parsing (K1).

struct InlineParser {
    let defs: DefinitionStore

    /// ASCII-punctuation characters a backslash can escape (CommonMark §2.4).
    private static let escapable: Set<Character> = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")

    /// Parses `text` into inline nodes: tokenize into literals and emphasis
    /// delimiters, pair the delimiters into emphasis/strong, then coalesce
    /// adjacent text.
    func parse(_ text: String, depth: Int) -> [MarkdownInline] {
        coalesceText(processEmphasis(tokenize(text, depth: depth)))
    }

    /// Scans `text` into `InlineToken`s: backslash escapes, code spans, footnote
    /// references, and reference links become `.literal`; `*`/`_` runs and `~`
    /// runs of ≥2 become `.delim` (with flanking). Text between delimiters is
    /// merged into one `.literal(.text(...))`; a lone `~` is literal text.
    func tokenize(_ text: String, depth: Int = 0) -> [InlineToken] {
        let chars = Array(text)
        var tokens: [InlineToken] = []
        var buf = ""
        func flushText() {
            if !buf.isEmpty { tokens.append(.literal(.text(buf))); buf = "" }
        }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, Self.escapable.contains(chars[i + 1]) {
                buf.append(chars[i + 1])
                i += 2
                continue
            }
            if c == "`" {
                var n = 0
                while i + n < chars.count, chars[i + n] == "`" { n += 1 }
                if let close = findClosingBacktickRun(chars, from: i + n, length: n) {
                    flushText()
                    tokens.append(.literal(.code(codeSpanContent(chars, from: i + n, to: close))))
                    i = close + n
                } else {
                    buf.append(String(repeating: "`", count: n))
                    i += n
                }
                continue
            }
            if c == "<", let (node, end) = parseAutolink(chars, from: i) {
                flushText()
                tokens.append(.literal(node))
                i = end
                continue
            }
            if c == "!" || c == "[" {
                // Inline link/image has precedence over emphasis: it is fully
                // resolved here and emitted as one literal token.
                if let (node, end) = parseInlineLinkOrImage(chars, from: i) {
                    flushText()
                    tokens.append(.literal(node))
                    i = end
                    continue
                }
            }
            if c == "[", i + 1 < chars.count, chars[i + 1] == "^",
               let (id, end) = scanFootnoteRef(chars, from: i), defs.hasFootnote(id) {
                flushText()
                tokens.append(.literal(.footnoteReference(id: id)))
                i = end
                continue
            }
            if c == "!" || c == "[" {
                if let (node, end) = parseReferenceLinkOrImage(chars, from: i) {
                    flushText()
                    tokens.append(.literal(node))
                    i = end
                    continue
                }
            }
            if c == "*" || c == "_" || c == "~" {
                var n = 0
                while i + n < chars.count, chars[i + n] == c { n += 1 }
                if c == "~", n < 2 {
                    buf.append(String(repeating: "~", count: n))
                    i += n
                    continue
                }
                let before: Character? = i > 0 ? chars[i - 1] : nil
                let after: Character? = i + n < chars.count ? chars[i + n] : nil
                let flank = classifyFlanking(char: c, before: before, after: after)
                flushText()
                tokens.append(.delim(char: c, count: n, origCount: n,
                                     canOpen: flank.canOpen, canClose: flank.canClose))
                i += n
                continue
            }
            buf.append(c)
            i += 1
        }
        flushText()
        return tokens
    }

    /// Parses an inline link `[text](dest "title")` or image `![alt](src "title")`
    /// at `chars[start]`, returning the resolved node and the index just past the
    /// closing `)`, or nil if it is not a well-formed inline link/image.
    func parseInlineLinkOrImage(_ chars: [Character], from start: Int) -> (MarkdownInline, Int)? {
        var i = start
        let isImage = chars[i] == "!"
        if isImage {
            guard i + 1 < chars.count, chars[i + 1] == "[" else { return nil }
            i += 1
        }
        guard i < chars.count, chars[i] == "[" else { return nil }
        let textOpen = i
        guard let textClose = matchBracket(chars, openAt: textOpen) else { return nil }
        let parenOpen = textClose + 1
        guard parenOpen < chars.count, chars[parenOpen] == "(",
              let parenClose = matchParen(chars, openAt: parenOpen) else { return nil }
        let interior = String(chars[(textOpen + 1)..<textClose])
        let parenInner = String(chars[(parenOpen + 1)..<parenClose])
        guard let (dest, title) = splitDestinationAndTitle(parenInner) else { return nil }
        if isImage {
            return (.image(source: dest, title: title, alt: inlinesToPlainText(parse(interior, depth: 0))), parenClose + 1)
        }
        return (.link(destination: dest, title: title, content: parse(interior, depth: 0)), parenClose + 1)
    }

    /// Reduces inline nodes to their plain-text content (image alt text): drops
    /// emphasis/link markup, keeps code/text/alt/url, maps breaks to a space.
    func inlinesToPlainText(_ inlines: [MarkdownInline]) -> String {
        var out = ""
        for inline in inlines {
            switch inline {
            case .text(let t): out += t
            case .code(let c): out += c
            case .emphasis(let c), .strong(let c), .strikethrough(let c): out += inlinesToPlainText(c)
            case .link(_, _, let c): out += inlinesToPlainText(c)
            case .image(_, _, let alt): out += alt
            case .autolink(let url): out += url
            case .footnoteReference(let id): out += "[^\(id)]"
            case .softBreak, .hardBreak: out += " "
            }
        }
        return out
    }

    /// Finds the index of a closing backtick run of exactly `n` backticks at or
    /// after `start` (runs of other lengths are skipped as content), or nil.
    private func findClosingBacktickRun(_ chars: [Character], from start: Int, length n: Int) -> Int? {
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

    /// Code-span content `chars[start..<end]`, stripping one leading and one
    /// trailing space iff both edges are spaces and it is not all spaces (§6.3).
    private func codeSpanContent(_ chars: [Character], from start: Int, to end: Int) -> String {
        var content = String(chars[start..<end])
        if content.count >= 2, content.first == " ", content.last == " ",
           !content.allSatisfy({ $0 == " " }) {
            content = String(content.dropFirst().dropLast())
        }
        return content
    }

    /// Scans a footnote reference `[^id]` at `chars[start]` (`[`), returning the
    /// id and the index just past the closing `]`, or nil if malformed.
    private func scanFootnoteRef(_ chars: [Character], from start: Int) -> (String, Int)? {
        var j = start + 2 // skip `[^`
        var id = ""
        while j < chars.count, chars[j] != "]" {
            if chars[j] == "[" { return nil }
            id.append(chars[j])
            j += 1
        }
        guard j < chars.count, !id.isEmpty else { return nil }
        return (id, j + 1)
    }

    /// Parses a reference link/image at `chars[start]`: full `[text][label]`,
    /// collapsed `[text][]`, or shortcut `[text]` (and the `![...]` image forms),
    /// resolved against `defs`. Uses `matchBracket` so escapes and code spans in
    /// the text are honored. Returns nil if the label does not resolve.
    func parseReferenceLinkOrImage(_ chars: [Character], from start: Int) -> (MarkdownInline, Int)? {
        var i = start
        let isImage = chars[i] == "!"
        if isImage {
            guard i + 1 < chars.count, chars[i + 1] == "[" else { return nil }
            i += 1
        }
        guard i < chars.count, chars[i] == "[" else { return nil }
        let textOpen = i
        guard let textClose = matchBracket(chars, openAt: textOpen) else { return nil }
        let interior = String(chars[(textOpen + 1)..<textClose])

        var label = interior // shortcut form
        var end = textClose + 1
        if textClose + 1 < chars.count, chars[textClose + 1] == "[" {
            let labelOpen = textClose + 1
            guard let labelClose = matchBracket(chars, openAt: labelOpen) else { return nil }
            let labelInterior = String(chars[(labelOpen + 1)..<labelClose])
            label = labelInterior.isEmpty ? interior : labelInterior // collapsed reuses the text
            end = labelClose + 1
        }
        guard let def = defs.link(for: label) else { return nil }
        if isImage {
            return (.image(source: def.destination, title: def.title,
                           alt: inlinesToPlainText(parse(interior, depth: 0))), end)
        }
        return (.link(destination: def.destination, title: def.title, content: parse(interior, depth: 0)), end)
    }
}
