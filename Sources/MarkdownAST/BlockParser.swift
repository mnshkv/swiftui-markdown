// Block scanner (Pass A): produces a `[RawBlock]` tree of raw leaves.
//
// At this wave it only emits `.paragraph(raw:)`. Other block constructs
// (headings, lists, block quotes, code blocks, tables, etc.) are added by
// later Wave 3 tasks. Pass B (resolving `[RawBlock]` into the public
// `[MarkdownBlock]` AST with parsed inlines) lands in a later task.

/// Pass A block scanner. Accumulates paragraph lines and splits paragraphs on
/// blank lines. Recursion guard `depth` is accepted for later tasks but unused
/// here (a hard ceiling keeps behaviour safe even before recursion is added).
struct BlockParser {
    let defs: DefinitionStore

    /// Maximum nesting depth for recursive block parsing (recursion guard for
    /// later tasks). Reached only by pathologically nested input.
    static let maxDepth: Int = 512

    /// Parse preprocessed (tab-expanded) lines into a flat list of raw blocks.
    func parse(_ lines: [String], depth: Int) -> [RawBlock] {
        guard depth < Self.maxDepth else { return [] }

        var blocks: [RawBlock] = []
        var pending: [String] = []

        func flush() {
            guard !pending.isEmpty else { return }
            blocks.append(.paragraph(raw: pending.joined(separator: "\n")))
            pending.removeAll(keepingCapacity: true)
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            if isBlank(line) {
                flush()
            } else if let h = atxHeading(Substring(line)) {
                // ATX headings interrupt a pending paragraph.
                flush()
                blocks.append(.heading(level: h.level, raw: h.raw))
            } else {
                pending.append(trimWhitespace(line))
            }
            i += 1
        }
        flush()

        return blocks
    }

    /// Attempts to recognize an ATX heading (CommonMark §4.2) in `line`.
    ///
    /// Rules: 0–3 leading spaces (4+ ⇒ not a heading); 1–6 `#` followed by a
    /// space or end-of-line; a trailing `#` run is stripped only if preceded
    /// by a space; the final text is whitespace-trimmed.
    private func atxHeading(_ line: Substring) -> (level: Int, raw: String)? {
        let s = stripUpTo3Spaces(line)
        guard let first = s.first, first == "#" else { return nil }

        // Count the leading `#` run (1..=6).
        var idx = s.startIndex
        var hashes = 0
        while idx < s.endIndex, s[idx] == "#" {
            hashes += 1
            idx = s.index(after: idx)
        }
        guard hashes >= 1, hashes <= 6 else { return nil }

        // The char after the `#` run must be a space or end-of-line.
        if idx < s.endIndex {
            guard s[idx] == " " else { return nil }
            // Skip the single separating space.
            idx = s.index(after: idx)
        }

        // `rest` is the heading text after the `#`-run + one space.
        var rest = s[idx...]

        // Strip a trailing `#` run ONLY if preceded by a space.
        // Walk back over trailing whitespace? No — CommonMark: the closing
        // run is the final sequence of `#` chars; it is stripped only if the
        // character immediately before it is a space. Any whitespace between
        // the text and the closing run is also trimmed at the end.
        if let last = rest.last, last == "#" {
            // Count trailing `#` chars.
            var tailCount = 0
            var j = rest.endIndex
            while j > rest.startIndex {
                let prev = rest.index(before: j)
                if rest[prev] == "#" {
                    tailCount += 1
                    j = prev
                } else {
                    break
                }
            }
            // `j` is the index just before the trailing `#` run.
            // The run is stripped only if the preceding char is a space.
            if j > rest.startIndex {
                let before = rest.index(before: j)
                if rest[before] == " " {
                    rest = rest[rest.startIndex..<before]
                }
                // else: keep the `#` run (no preceding space).
            } else {
                // The whole `rest` is a `#` run (e.g. `## #` → rest was `#`).
                // `j == rest.startIndex` means everything was `#`; with an
                // empty text before it, there is no preceding space char, but
                // the separating space was already consumed. CommonMark treats
                // `## #` as an empty heading, so strip the run.
                rest = rest[rest.startIndex..<j]
            }
        }

        // Trim leading/trailing whitespace from the final text.
        var text = rest
        while let f = text.first, f.isWhitespace { text = text.dropFirst() }
        while let l = text.last, l.isWhitespace { text = text.dropLast() }

        return (level: hashes, raw: String(text))
    }

    /// True iff `line` is empty or contains only whitespace.
    private func isBlank(_ line: String) -> Bool {
        // `allSatisfy` on an empty String returns true — correct for blank input.
        line.allSatisfy { $0.isWhitespace }
    }

    /// Trim leading and trailing whitespace (spaces, tabs, etc.) from `line`
    /// without Foundation.
    private func trimWhitespace(_ line: String) -> String {
        var s = Substring(line)
        while let first = s.first, first.isWhitespace { s = s.dropFirst() }
        while let last = s.last, last.isWhitespace { s = s.dropLast() }
        return String(s)
    }
}