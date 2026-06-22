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
            } else {
                pending.append(trimWhitespace(line))
            }
            i += 1
        }
        flush()

        return blocks
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