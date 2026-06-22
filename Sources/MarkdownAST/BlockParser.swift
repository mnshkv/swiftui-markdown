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
            } else if isThematicBreakLine(line) {
                // A thematic break interrupts a paragraph (CommonMark §4.1).
                // NOTE: `para\n---` is a setext underline, not a thematic break,
                // but setext is T16 (not yet implemented). Until T16 lands, that
                // case is mis-handled as `[.paragraph("para"), .thematicBreak]`;
                // T16 will insert a setext check (only when a paragraph is
                // pending) BEFORE this branch.
                flush()
                blocks.append(.thematicBreak)
            } else if let h = atxHeading(Substring(line)) {
                // ATX headings interrupt a pending paragraph.
                flush()
                blocks.append(.heading(level: h.level, raw: h.raw))
            } else if let fence = fenceOpener(Substring(line)) {
                // Fenced code blocks interrupt a pending paragraph (CommonMark §4.5).
                flush()
                // Consume content lines until a matching closer is found or EOF.
                var content: [String] = []
                i += 1
                while i < lines.count {
                    let cl = lines[i]
                    if isFenceCloser(Substring(cl), of: fence) {
                        break
                    }
                    content.append(stripIndent(cl, indent: fence.indent))
                    i += 1
                }
                // If the loop ended because of a closer, `i` points at it; we fall
                // through and the outer `i += 1` advances past it. If it ended at
                // EOF, `i == lines.count` and the outer loop terminates.
                blocks.append(.codeBlock(language: fence.language, code: content.joined(separator: "\n")))
            } else {
                pending.append(trimWhitespace(line))
            }
            i += 1
        }
        flush()

        return blocks
    }

    /// True iff `line` is a thematic break (CommonMark §4.1), honoring the
    /// 4-space indented-code gate. `isThematicBreak` (in `Containers.swift`)
    /// operates on an already-`stripUpTo3Spaces`'d line and does NOT reject a
    /// leading-space prefix, so we gate here: when the original line has ≥4
    /// leading spaces, `stripUpTo3Spaces` returns it unchanged and
    /// `stripped.first == " "` ⇒ fall through (indented code, not a break).
    private func isThematicBreakLine(_ line: String) -> Bool {
        let stripped = stripUpTo3Spaces(Substring(line))
        guard stripped.first != " " else { return false }
        return isThematicBreak(stripped)
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

    // MARK: - Fenced code blocks (CommonMark §4.5)

    /// Captured opener metadata for matching the closer.
    private struct Fence {
        let char: Character
        let count: Int
        let language: String?
        let indent: Int
    }

    /// Attempts to recognize a fenced-code-block opening fence in `line`.
    ///
    /// Rules: 0–3 leading spaces (4+ ⇒ not a fence); a run of ≥3 backticks OR
    /// ≥3 tildes; an info string after the run. For backtick fences the info
    /// string must NOT contain a backtick (otherwise the line is not a valid
    /// opener). For tilde fences the info string may contain anything.
    /// `language` is the first whitespace-delimited word of the trimmed info
    /// string, or `nil` if the info string is empty/whitespace-only.
    private func fenceOpener(_ line: Substring) -> Fence? {
        // Count 0–3 leading spaces. ≥4 ⇒ not a fence (indented-code territory).
        var indent = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == " " {
            indent += 1
            idx = line.index(after: idx)
        }
        guard indent <= 3 else { return nil }

        // Need a fence char next.
        guard idx < line.endIndex else { return nil }
        let ch = line[idx]
        guard ch == "`" || ch == "~" else { return nil }

        // Count the fence-char run (must be ≥3).
        var count = 0
        while idx < line.endIndex, line[idx] == ch {
            count += 1
            idx = line.index(after: idx)
        }
        guard count >= 3 else { return nil }

        // The remainder is the info string.
        let info = line[idx...]

        // Backtick fences: info string must not contain a backtick.
        if ch == "`", info.contains("`") { return nil }

        // Language = first whitespace-delimited word of the trimmed info string.
        // Trailing spaces in the info string are ignored.
        var language: String? = nil
        var infoIter = info
        while let f = infoIter.first, f.isWhitespace { infoIter = infoIter.dropFirst() }
        if !infoIter.isEmpty {
            // Collect up to the next whitespace.
            var word = infoIter
            var endIdx = word.startIndex
            while endIdx < word.endIndex, !word[endIdx].isWhitespace {
                endIdx = word.index(after: endIdx)
            }
            word = word[word.startIndex..<endIdx]
            if !word.isEmpty { language = String(word) }
        }

        return Fence(char: ch, count: count, language: language, indent: indent)
    }

    /// True iff `line` is a matching closing fence for `fence`.
    ///
    /// Rules: 0–3 leading spaces (strip them); a run of the SAME fence char of
    /// length ≥ `fence.count`; then ONLY trailing whitespace (nothing else).
    /// Non-whitespace after the run ⇒ not a closer (it's content).
    private func isFenceCloser(_ line: Substring, of fence: Fence) -> Bool {
        // Strip 0–3 leading spaces. ≥4 leading spaces ⇒ not a closer (content).
        var leading = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == " " {
            leading += 1
            idx = line.index(after: idx)
        }
        guard leading <= 3 else { return false }

        // Count the fence-char run.
        var count = 0
        while idx < line.endIndex, line[idx] == fence.char {
            count += 1
            idx = line.index(after: idx)
        }
        guard count >= fence.count else { return false }

        // The remainder must be only whitespace.
        let rest = line[idx...]
        return rest.allSatisfy { $0.isWhitespace }
    }

    /// Strips exactly `indent` leading spaces from `line`. If `line` has fewer
    /// leading spaces, strips as many as present (never goes negative, never
    /// pads). Content is otherwise kept literal (no internal/trailing trim).
    private func stripIndent(_ line: String, indent: Int) -> String {
        var stripped = 0
        var s = Substring(line)
        while stripped < indent, let f = s.first, f == " " {
            s = s.dropFirst()
            stripped += 1
        }
        return String(s)
    }
}