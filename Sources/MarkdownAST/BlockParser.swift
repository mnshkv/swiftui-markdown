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

        // Emits any accumulated paragraph lines as a single paragraph block and
        // clears the buffer.
        func flush() {
            guard !pending.isEmpty else { return }
            blocks.append(.paragraph(raw: pending.joined(separator: "\n")))
            pending.removeAll(keepingCapacity: true)
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // Setext heading (CommonMark §4.3). A setext heading is a pending
            // paragraph followed by a setext underline line (`=` run → h1,
            // `-` run → h2). This branch MUST precede the thematic-break and
            // table branches: `Title\n---` is an h2 (setext), not a thematic
            // break, and `para\n---` is an h2, not a GFM table (the table
            // branch's `Title` header + `---` delimiter would otherwise match).
            // The `!pending.isEmpty` guard is the disambiguator: a LONE `---`
            // (no pending paragraph) skips this branch and reaches the
            // thematic-break branch → thematic break (T9 behavior preserved).
            if !pending.isEmpty, let level = setextUnderlineLevel(line) {
                blocks.append(.heading(level: level, raw: pending.joined(separator: "\n")))
                pending.removeAll(keepingCapacity: true)
                i += 1 // consume only the underline line; pending lines were
                       // already consumed by accumulation.
                continue
            }

            // Indented code block (CommonMark §4.4). Placed BEFORE the
            // thematic/ATX/fenced-code branches and guarded by
            // `pending.isEmpty`: indented code CANNOT interrupt a paragraph
            // (§4.4), so `text\n    more` keeps `    more` as a lazy paragraph
            // continuation. The `hasPrefix("    ")` predicate matches ONLY
            // ≥4-space-indented lines; the thematic/ATX/fence constructs
            // require ≤3 leading spaces (they use `stripUpTo3Spaces` and need
            // a non-space first char after stripping). So placing this branch
            // first makes `    ---` / `    # H` / `    ``` ` correctly code,
            // while `---` / `   ---` (0–3 spaces) skip it and reach their
            // own branches — robustly, without depending on the other
            // branches' internal ≥4-space rejection.
            if pending.isEmpty, isIndentedCode(line) {
                var content: [String] = [String(line.dropFirst(4))]
                i += 1
                while i < lines.count {
                    let cl = lines[i]
                    if isIndentedCode(cl) {
                        content.append(String(cl.dropFirst(4)))
                        i += 1
                    } else if isBlank(cl) {
                        // Peek past consecutive blanks to the next non-blank.
                        var j = i + 1
                        while j < lines.count, isBlank(lines[j]) { j += 1 }
                        if j < lines.count, isIndentedCode(lines[j]) {
                            // Blank continues the code block (internal blank).
                            // Consume just THIS blank as an empty content line;
                            // the loop re-peeks the next blank individually,
                            // preserving multiple internal blanks.
                            content.append("")
                            i += 1
                        } else {
                            // Next non-blank is not indented, or EOF → the
                            // blank is TRAILING. Stop without consuming it;
                            // leave `i` for the outer loop (decrement so the
                            // outer `i += 1` re-lands on the blank, matching
                            // the blockquote/footnote idiom).
                            i -= 1
                            break
                        }
                    } else {
                        // Non-blank, <4 leading spaces → code block ends.
                        // Leave this line for the outer loop.
                        i -= 1
                        break
                    }
                }
                blocks.append(.codeBlock(language: nil, code: content.joined(separator: "\n")))
            } else if isBlank(line) {
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
            } else if let inner0 = blockquoteMarker(Substring(line)) {
                // Block quotes interrupt a pending paragraph (CommonMark §5.1).
                flush()
                // Collect inner content lines: the first marker line (already
                // stripped → `inner0`), then subsequent lines that either:
                //  • have a blockquote marker (strip it → inner line, may be ""), OR
                //  • are a lazy continuation: non-blank AND not a block-start
                //    (K3/F4 guard — a heading/fence/new-list after `> para` starts
                //    a SIBLING, not a quote continuation).
                // A non-marker line that is blank or a block-start ENDS the quote;
                // the line is left for the outer dispatcher (decrement i so the
                // outer `i += 1` re-lands on it).
                var inner: [String] = [String(inner0)]
                i += 1
                while i < lines.count {
                    let cl = lines[i]
                    if let stripped = blockquoteMarker(Substring(cl)) {
                        inner.append(String(stripped))
                        i += 1
                    } else {
                        let s = stripUpTo3Spaces(Substring(cl))
                        if !s.isEmpty && !isBlockStart(Substring(cl)) {
                            // Lazy continuation: include the line verbatim.
                            inner.append(cl)
                            i += 1
                        } else {
                            // Blank or block-start → end of quote; leave this line
                            // for the outer loop. Step back so the outer `i += 1`
                            // re-processes it.
                            i -= 1
                            break
                        }
                    }
                }
                let sub = BlockParser(defs: defs).parse(inner, depth: depth + 1)
                blocks.append(.blockQuote(blocks: sub))
            } else if pending.isEmpty, linkReferenceDefinition(line) {
                // Link reference definition (CommonMark §6.1). Cannot interrupt
                // a paragraph (§6.1 ex 213) — guarded by `pending.isEmpty`.
                // Collected into `defs`; the line is removed from the block
                // output (no RawBlock emitted). Just advance.
                //
                // Checked BEFORE the table branch: a `[^id]:` or `[label]:`
                // line would otherwise be caught by the table branch (which
                // tries a delimiter match on the next line, fails, and falls to
                // paragraph-accumulate), swallowing the def into the paragraph.
            } else if pending.isEmpty, let fn = footnoteDefinition(lines, from: i) {
                // Footnote definition (extended syntax). Same paragraph-interrupt
                // guard as link-ref-defs. The body (first line + indented
                // continuation lines, blanks kept for multi-paragraph) is stored
                // as raw lines; Pass B resolves them. Advance past consumed
                // lines; the outer `i += 1` re-lands on the terminator (or EOF).
                defs.addFootnote(id: fn.id, bodyLines: fn.bodyLines)
                i += fn.consumed - 1
            } else if pending.isEmpty, i + 1 < lines.count, setextUnderlineLevel(lines[i + 1]) == nil,
                      listMarker(Substring(line)) == nil {
                // (A line that is a valid list marker is a list item, not a
                // table header — let it fall through to the list branch below.)
                // GFM table (§4.6). Tables cannot interrupt a paragraph (F7):
                // only start one when the pending paragraph is empty. The
                // header is `lines[i]`; the delimiter is `lines[i+1]`;
                // subsequent lines are data rows until a blank line or another
                // block-start.
                //
                // GFM tables allow 0–3 leading spaces of indentation (like
                // other block constructs); 4+ leading spaces is indented-code
                // territory and must NOT be a table. We strip up to 3 leading
                // spaces from the header, delimiter, and each data-row line
                // BEFORE passing them to `splitTableRow`/`delimiterAlignments`
                // (single strip site — the helpers themselves stay
                // indentation-agnostic). `stripUpTo3Spaces` returns a line
                // with ≥4 leading spaces unchanged, so the 4-space case leaves
                // leading spaces in place; the stripped header's first char is
                // then a space (not `|`) and the stripped delimiter's first
                // cell is empty/whitespace, failing `:?-+:?` → not a table →
                // falls through to paragraph (correct).
                let headerLine = stripUpTo3Spaces(Substring(line))
                let delimiterLine = stripUpTo3Spaces(Substring(lines[i + 1]))
                // ≥4 leading spaces on the header ⇒ indented-code/paragraph
                // territory, not a table.
                //
                // A GFM table must contain at least one `|`: a single-column
                // delimiter like `-:`/`:--` is a valid alignment shape but a
                // pipe-less line followed by it is ordinary prose, not a table.
                guard headerLine.first != " ",
                      headerLine.contains("|") || delimiterLine.contains("|"),
                      let alignments = delimiterAlignments(String(delimiterLine))
                else {
                    pending.append(trimWhitespace(line))
                    i += 1
                    continue
                }

                let headerCells = splitTableRow(String(headerLine))
                let width = headerCells.count

                // Guard: the delimiter cell count must equal the header cell
                // count (GFM spec). `delimiterAlignments` already produced a
                // non-nil array, but its length is the delimiter's cell count;
                // if it differs from the header width, this is not a table.
                guard alignments.count == width else {
                    pending.append(trimWhitespace(line))
                    i += 1
                    continue
                }

                i += 2 // advance past header + delimiter
                var rows: [[String]] = []
                while i < lines.count {
                    let cl = lines[i]
                    if isBlank(cl) || isBlockStart(Substring(cl)) {
                        // The terminating line (blank or block-start) is left
                        // for the outer dispatcher: step back so the outer
                        // `i += 1` re-lands on it.
                        i -= 1
                        break
                    }
                    let rowLine = stripUpTo3Spaces(Substring(cl))
                    var cells = splitTableRow(String(rowLine))
                    // Normalize cell count to header width: pad or truncate.
                    if cells.count < width {
                        cells.append(contentsOf: Array(repeating: "", count: width - cells.count))
                    } else if cells.count > width {
                        cells = Array(cells.prefix(width))
                    }
                    rows.append(cells)
                    i += 1
                }
                blocks.append(.table(RawTable(
                    alignments: alignments,
                    header: [headerCells],
                    rows: rows
                )))
            } else if pending.count == 1, let dc = detailLineContent(line) {
                // Definition list (PHP-Markdown-Extra style). Trigger: the
                // current line is a `:`-led detail line AND the pending
                // paragraph has exactly ONE line (the term). A `:` line
                // without a one-line term falls through to paragraph text.
                let term = pending[0]
                pending.removeAll(keepingCapacity: true)
                var definitions: [RawDefinition] = []
                var curDef = RawDefinition(term: term, details: [])
                // The first `: content` line is already consumed as the
                // trigger; seed the first detail's content with it.
                var curDetailLines: [String] = [dc]
                var inDetail = true
                i += 1
                while i < lines.count {
                    let l = lines[i]
                    if let d = detailLineContent(l) {
                        // Each `:` line starts a NEW detail entry.
                        if inDetail {
                            curDef.details.append(
                                BlockParser(defs: defs).parse(curDetailLines, depth: depth + 1)
                            )
                            curDetailLines = []
                        }
                        curDetailLines = [d]
                        inDetail = true
                        i += 1
                    } else if isIndentedContinuation(l) {
                        // Leading-whitespace, non-blank, non-`:` line folds
                        // into the CURRENT detail's content (raw, indent
                        // kept — `parse` per-line-trims it).
                        curDetailLines.append(l)
                        i += 1
                    } else if isBlank(l) {
                        // Blank line ends the list. Decrement-reland so the
                        // outer `i += 1` re-lands on the blank as a sibling.
                        i -= 1
                        break
                    } else {
                        // Non-indented, non-`:`, non-blank → potential new
                        // term. Close the current detail first.
                        if inDetail {
                            curDef.details.append(
                                BlockParser(defs: defs).parse(curDetailLines, depth: depth + 1)
                            )
                            curDetailLines = []
                            inDetail = false
                        }
                        if i + 1 < lines.count, detailLineContent(lines[i + 1]) != nil {
                            // Lookahead: next line is `:`-led → this line is a
                            // new term in the SAME definition list.
                            definitions.append(curDef)
                            curDef = RawDefinition(term: trimWhitespace(l), details: [])
                            i += 1
                        } else {
                            // Not a new term → end of list (decrement-reland).
                            i -= 1
                            break
                        }
                    }
                }
                if inDetail {
                    curDef.details.append(
                        BlockParser(defs: defs).parse(curDetailLines, depth: depth + 1)
                    )
                }
                definitions.append(curDef)
                blocks.append(.definitionList(definitions))
            }
            // K2 ordering point (Task 19 — dispatch ordering guard):
            // Task 20 inserts the LIST dispatch branch HERE — as a new
            // `else if` between the definition-list branch above and the
            // paragraph-accumulate fallback below — AFTER the thematic-break
            // branch (which runs near the top of this chain, at the
            // `isThematicBreakLine(line)` check). This ordering is MANDATORY:
            // thematic-break-shaped lines such as `- - -`, `* * *`, and `---`
            // are ALSO syntactically valid bullet list markers per the Task 18
            // `listMarker(_:)` recognizer (e.g. `- - -` is a `-` bullet followed
            // by content `- -`, markerWidth 2). CommonMark §4.2 resolves the
            // ambiguity by PRECEDENCE: the thematic-break construct is checked
            // BEFORE the list construct, so `- - -` → `.thematicBreak`, NOT a
            // 1-item list. If Task 20 places the list branch ABOVE the thematic
            // branch, `- - -`/`* * *`/`---` would wrongly become lists and the
            // Task 19 regression tests in `ThematicBreakTests.swift` would
            // fail. Keep the list branch BELOW thematic (i.e. at this point).
            else if let firstMarker = listMarker(Substring(line)),
                    pending.isEmpty || canInterruptParagraph(Substring(line)) {
                // List (CommonMark §5.2). A list interrupts a pending paragraph
                // only when `canInterruptParagraph` allows it (a bullet, or a
                // `1.`-start ordered list, with a non-empty first item).
                flush()
                let (listBlock, next) = parseList(lines, from: i, firstMarker: firstMarker, depth: depth)
                blocks.append(listBlock)
                i = next - 1 // outer `i += 1` re-lands on the first unconsumed line
            }
            else {
                pending.append(trimWhitespace(line))
            }
            i += 1
        }
        flush()

        return blocks
    }

    /// Number of leading ASCII spaces in `line`.
    private func leadingSpaceCount(_ line: String) -> Int {
        var n = 0
        for ch in line { if ch == " " { n += 1 } else { break } }
        return n
    }

    /// Parses a list starting at `arr[start]`, collecting consecutive same-kind
    /// items. Each item's lines (marker remainder + continuation/nested lines,
    /// indent-stripped) are parsed recursively at `depth + 1` so nesting comes
    /// for free. The list is loose if any blank line separates two block-level
    /// children (between items or inside an item); a trailing blank is ignored.
    /// Returns the list and the index of the first unconsumed line.
    private func parseList(_ arr: [String], from start: Int, firstMarker: ListMarker, depth: Int) -> (RawBlock, Int) {
        let kind = firstMarker.kind
        let bullet = firstMarker.bullet
        let delimiter = firstMarker.orderedDelimiter
        var items: [RawListItem] = []
        var isLoose = false
        var i = start
        while i < arr.count {
            // Each item begins with a same-kind marker (same bullet char, or
            // same ordered delimiter). A change in bullet/delimiter ends the list.
            guard let lm = listMarker(Substring(arr[i])),
                  lm.bullet == bullet, lm.orderedDelimiter == delimiter
            else { break }
            let contentStart = lm.contentStart
            // The marker remainder is the item's first content line.
            var itemLines: [String] = [String(arr[i].dropFirst(contentStart))]
            i += 1
            itemLoop: while i < arr.count {
                let cl = arr[i]
                if isBlank(cl) {
                    // Peek past consecutive blanks to the next non-blank line to
                    // decide whether the blank is internal (loose) or trailing.
                    var j = i
                    while j < arr.count, isBlank(arr[j]) { j += 1 }
                    if j >= arr.count {
                        i = j // trailing blank(s) — consumed, not a looseness signal
                        break itemLoop
                    }
                    let nextLine = arr[j]
                    if leadingSpaceCount(nextLine) >= contentStart {
                        // Blank between two blocks inside the item → loose.
                        isLoose = true
                        while i < j { itemLines.append(""); i += 1 }
                    } else if let nm = listMarker(Substring(nextLine)),
                              nm.bullet == bullet, nm.orderedDelimiter == delimiter {
                        // Blank between two items of this list → loose.
                        isLoose = true
                        i = j
                        break itemLoop
                    } else {
                        // Blank then a non-continuation line → the list ends.
                        i = j
                        break itemLoop
                    }
                } else if leadingSpaceCount(cl) >= contentStart {
                    itemLines.append(stripIndent(cl, indent: contentStart))
                    i += 1
                } else if listMarker(Substring(cl)) != nil {
                    break itemLoop // outer-indent marker → next item / sibling list
                } else if !isBlockStart(Substring(cl)) {
                    itemLines.append(cl) // lazy paragraph continuation
                    i += 1
                } else {
                    break itemLoop // outer-indent block start (K3) ends the item
                }
            }
            let blocks = BlockParser(defs: defs).parse(itemLines, depth: depth + 1)
            items.append(RawListItem(blocks: blocks, task: nil))
        }
        return (.list(RawList(kind: kind, isTight: !isLoose, items: items)), i)
    }

    /// Returns the setext-heading level (1 for `=`, 2 for `-`) if `line` is a
    /// setext underline (CommonMark §4.3), otherwise `nil`.
    private func setextUnderlineLevel(_ line: String) -> Int? {
        let s = stripUpTo3Spaces(Substring(line))
        // `stripUpTo3Spaces` returns a ≥4-space-indented line unchanged, so
        // `s.first == " "` rejects the 4-space case (and any blank line).
        guard let first = s.first, first == "=" || first == "-" else { return nil }
        let ch = first
        // Contiguous run of `ch` (≥1 — `first` guarantees at least one).
        var idx = s.startIndex
        while idx < s.endIndex, s[idx] == ch { idx = s.index(after: idx) }
        // After the run, only trailing whitespace is allowed.
        let rest = s[idx...]
        guard rest.allSatisfy({ $0.isWhitespace }) else { return nil }
        return ch == "=" ? 1 : 2
    }

    /// True iff `line` is a thematic break (CommonMark §4.1), honoring the
    /// 4-space indented-code gate.
    private func isThematicBreakLine(_ line: String) -> Bool {
        let stripped = stripUpTo3Spaces(Substring(line))
        guard stripped.first != " " else { return false }
        return isThematicBreak(stripped)
    }

    /// Recognizes an ATX heading (CommonMark §4.2) in `line`, returning its
    /// level and trimmed text, or `nil` if `line` is not an ATX heading.
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

    /// True iff `c` is an ASCII space (U+0020) or tab (U+0009); Unicode
    /// whitespace such as NBSP is treated as ordinary content (CommonMark).
    private func isSpaceOrTab(_ c: Character) -> Bool {
        c == " " || c == "\t"
    }

    /// True iff `line` is empty or contains only ASCII spaces/tabs.
    private func isBlank(_ line: String) -> Bool {
        // `allSatisfy` on an empty String returns true — correct for blank input.
        line.allSatisfy { isSpaceOrTab($0) }
    }

    /// Trims leading and trailing ASCII spaces/tabs from `line`; Unicode
    /// whitespace is preserved as content (see `isSpaceOrTab`).
    private func trimWhitespace(_ line: String) -> String {
        var s = Substring(line)
        while let first = s.first, isSpaceOrTab(first) { s = s.dropFirst() }
        while let last = s.last, isSpaceOrTab(last) { s = s.dropLast() }
        return String(s)
    }

    // MARK: - Block quotes (CommonMark §5.1)

    /// Recognizes a blockquote marker (0–3 spaces, `>`, one optional space) and
    /// returns the inner content, or `nil` if `line` does not begin a blockquote.
    private func blockquoteMarker(_ line: Substring) -> Substring? {
        let s = stripUpTo3Spaces(line)
        guard s.first == ">" else { return nil }
        var rest = s.dropFirst()
        // Strip ONE optional following space or tab.
        if rest.first == " " || rest.first == "\t" {
            rest = rest.dropFirst()
        }
        return rest
    }

    // MARK: - Fenced code blocks (CommonMark §4.5)

    /// Captured opener metadata for matching the closer.
    private struct Fence {
        let char: Character
        let count: Int
        let language: String?
        let indent: Int
    }

    /// Recognizes a fenced-code-block opening fence (CommonMark §4.5) in `line`,
    /// returning its captured metadata, or `nil` if `line` is not an opener.
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
        var language: String?
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

    /// True iff `line` is a matching closing fence for `fence` (0–3 spaces, a
    /// run of the same char ≥ `fence.count`, then only trailing whitespace).
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

    /// Strips up to `indent` leading spaces from `line` (as many as present),
    /// keeping the rest literal.
    private func stripIndent(_ line: String, indent: Int) -> String {
        var stripped = 0
        var s = Substring(line)
        while stripped < indent, let f = s.first, f == " " {
            s = s.dropFirst()
            stripped += 1
        }
        return String(s)
    }

    // MARK: - Definition lists (PHP-Markdown-Extra style)

    /// Recognizes a definition-list detail line (0–3 spaces, `:`, one optional
    /// space) and returns its content, or `nil` if `line` is not a detail line.
    private func detailLineContent(_ line: String) -> String? {
        let s = stripUpTo3Spaces(Substring(line))
        guard s.first == ":" else { return nil }
        var rest = s.dropFirst()
        if rest.first == " " || rest.first == "\t" {
            rest = rest.dropFirst()
        }
        return String(rest)
    }

    /// True iff `line` is an indented continuation of the current definition
    /// detail: leading whitespace, non-blank, and not a `:`-led detail line.
    private func isIndentedContinuation(_ line: String) -> Bool {
        guard line.first?.isWhitespace == true else { return false }
        if isBlank(line) { return false }
        if detailLineContent(line) != nil { return false }
        return true
    }

    // MARK: - Link reference definitions (CommonMark §6.1)

    /// Parses `line` as a link reference definition `[label]: dest "title"`,
    /// registering it in `defs` and returning `true`, else `false` (CommonMark §6.1).
    private func linkReferenceDefinition(_ line: String) -> Bool {
        let s = stripUpTo3Spaces(Substring(line))
        guard s.first == "[" else { return false }
        let afterOpen = s.dropFirst()
        // `[^...]` is a footnote def, not a link-ref-def.
        guard afterOpen.first != "^" else { return false }
        // Find the closing `]` (simple scan — escaped `\]` not specially handled).
        guard let closeIdx = afterOpen.firstIndex(of: "]") else { return false }
        let label = String(afterOpen[afterOpen.startIndex..<closeIdx])
        // Label must contain at least one non-whitespace character.
        guard label.contains(where: { !$0.isWhitespace }) else { return false }

        let afterClose = afterOpen[afterOpen.index(after: closeIdx)...]
        guard afterClose.first == ":" else { return false }
        let afterColon = afterClose.dropFirst()

        // Skip optional whitespace before destination.
        var rest = afterColon
        while let f = rest.first, f.isWhitespace { rest = rest.dropFirst() }
        guard !rest.isEmpty else { return false }

        // Destination: bare or angle-bracketed.
        let destination: String
        if rest.first == "<" {
            let afterAngle = rest.dropFirst()
            guard let closeAngle = afterAngle.firstIndex(of: ">") else {
                return false
            }
            destination = String(afterAngle[afterAngle.startIndex..<closeAngle])
            rest = afterAngle[afterAngle.index(after: closeAngle)...]
        } else {
            var endIdx = rest.startIndex
            while endIdx < rest.endIndex, !rest[endIdx].isWhitespace {
                endIdx = rest.index(after: endIdx)
            }
            destination = String(rest[rest.startIndex..<endIdx])
            rest = rest[endIdx...]
        }

        // Title (optional): skip whitespace, then a quoted/parenthesized string.
        var afterDest = rest
        while let f = afterDest.first, f.isWhitespace { afterDest = afterDest.dropFirst() }

        var title: String?
        if !afterDest.isEmpty {
            let q = afterDest.first!
            if q == "\"" || q == "'" || q == "(" {
                let closeChar: Character = (q == "(") ? ")" : q
                let afterQuote = afterDest.dropFirst()
                guard let titleClose = afterQuote.firstIndex(of: closeChar) else {
                    return false
                }
                title = String(afterQuote[afterQuote.startIndex..<titleClose])
                afterDest = afterQuote[afterQuote.index(after: titleClose)...]
            } else {
                // Non-whitespace after destination that isn't a title opener ⇒ junk.
                return false
            }
        }

        // Trailing-junk rejection: after title (or destination), only whitespace.
        if !afterDest.allSatisfy({ $0.isWhitespace }) { return false }

        defs.addLink(label: label, destination: destination, title: title)
        return true
    }

    // MARK: - Footnote definitions (extended syntax)

    /// Result of a successful footnote-definition parse.
    private struct FootnoteParse {
        let id: String
        let bodyLines: [String]
        /// Number of lines consumed (including the `[^id]:` first line).
        let consumed: Int
    }

    /// Parses a footnote definition `[^id]: body` starting at `lines[start]`,
    /// returning the id, body lines, and lines consumed, or `nil` on failure.
    private func footnoteDefinition(_ lines: [String], from start: Int) -> FootnoteParse? {
        let line = lines[start]
        let s = stripUpTo3Spaces(Substring(line))
        guard s.first == "[" else { return nil }
        let afterOpen = s.dropFirst()
        guard afterOpen.first == "^" else { return nil }
        let afterCaret = afterOpen.dropFirst()
        guard let closeIdx = afterCaret.firstIndex(of: "]") else { return nil }
        let id = String(afterCaret[afterCaret.startIndex..<closeIdx])
        guard !id.isEmpty else { return nil }

        let afterClose = afterCaret[afterCaret.index(after: closeIdx)...]
        guard afterClose.first == ":" else { return nil }
        let afterColon = afterClose.dropFirst()

        // Strip one optional leading space from the first body line.
        var firstBody = afterColon
        if firstBody.first == " " { firstBody = firstBody.dropFirst() }
        var bodyLines: [String] = [String(firstBody)]

        var i = start + 1
        while i < lines.count {
            let cl = lines[i]
            if isBlank(cl) {
                // Peek past consecutive blanks to the next non-blank line.
                var j = i + 1
                while j < lines.count, isBlank(lines[j]) { j += 1 }
                if j < lines.count, isIndentedBy4(lines[j]) {
                    // Blank is part of the body (multi-paragraph separator).
                    bodyLines.append("")
                    i += 1
                } else {
                    // Blank ends the body; leave it for the outer loop.
                    break
                }
            } else if isIndentedBy4(cl) {
                bodyLines.append(String(cl.dropFirst(4)))
                i += 1
            } else {
                // Dedented non-blank line → body ends; leave it for the outer loop.
                break
            }
        }

        return FootnoteParse(id: id, bodyLines: bodyLines, consumed: i - start)
    }

    /// True iff `line` has ≥4 leading space characters (tab-expanded input).
    private func isIndentedBy4(_ line: String) -> Bool {
        var count = 0
        for ch in line {
            if ch == " " { count += 1 } else { break }
        }
        return count >= 4
    }

    /// True iff `line` begins an indented code block content line (CommonMark
    /// §4.4): ≥4 leading spaces and not entirely spaces (which would be blank).
    private func isIndentedCode(_ line: String) -> Bool {
        line.hasPrefix("    ") && !line.dropFirst(4).allSatisfy { $0 == " " }
    }
}
