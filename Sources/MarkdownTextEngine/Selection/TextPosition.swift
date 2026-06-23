import Foundation

// MARK: - TextPosition

/// A position within the document's flattened UTF-16 text space.
/// `index` is a UTF-16 code-unit offset into `flattenedText(_:)`.
public struct TextPosition: Comparable, Sendable {
    public var index: Int

    public init(index: Int) {
        self.index = index
    }

    public static func < (lhs: TextPosition, rhs: TextPosition) -> Bool {
        lhs.index < rhs.index
    }
}

// MARK: - TextRange

/// A range within the flattened text space. Always normalised so `start <= end`.
public struct TextRange: Sendable {
    public var start: TextPosition
    public var end: TextPosition

    /// Initialises and normalises so that `start <= end`.
    public init(start: TextPosition, end: TextPosition) {
        if start <= end {
            self.start = start
            self.end = end
        } else {
            self.start = end
            self.end = start
        }
    }
}

// MARK: - flattenedText

/// Returns the plain-text representation of the document in document order.
///
/// Rules:
/// - Walk blocks in order, inserting `"\n"` between **every** adjacent pair.
/// - `.paragraph`: concatenate inline runs recursively.
///   - `.text(s, _)` → `s`
///   - `.link(runs:_)` → recurse into inner runs
///   - `.lineBreak(hard: true)` → `"\n"`
///   - `.lineBreak(hard: false)` → `"\u{2028}"` (Unicode LINE SEPARATOR)
///   - `.inlineImage` → `"\u{FFFC}"` (U+FFFC OBJECT REPLACEMENT CHARACTER, 1 UTF-16 unit)
///     INDEX SPACE CONTRACT: this must equal the UTF-16 length of the placeholder inserted
///     by `buildAttributedString` for `.inlineImage` (also exactly 1 UTF-16 unit).
/// - `.image` block → the attachment's `alt` text (block-level image; see textForBlock).
/// - All other non-paragraph block types contribute an empty string.
public func flattenedText(_ doc: TextDocument) -> String {
    var parts: [String] = []
    for block in doc.blocks {
        parts.append(textForBlock(block))
    }
    return parts.joined(separator: "\n")
}

// MARK: - Private helpers

func textForBlock(_ block: Block) -> String {
    switch block {
    case .paragraph(let p):
        return textForRuns(p.runs)
    case .list(let list):
        // Concatenate all items' flattened text, joined by "\n" between items.
        // CONSISTENCY CONTRACT: every geometry helper that walks list item layouts
        // must use the same separator ("\n") and the same item order.
        return list.items.map { flattenedText($0) }.joined(separator: "\n")
    case .quote(let innerDoc):
        // The quote contributes its inner document's flattened text.
        // CONSISTENCY CONTRACT: geometry helpers recurse into `inner` DocumentLayout
        // using the same flattened text as produced by flattenedText(innerDoc).
        return flattenedText(innerDoc)

    case .table(let t):
        // CONSISTENCY CONTRACT for tables:
        // Rows are visited in order: [header, body row 0, body row 1, ...].
        // Within each row, cells are joined with "\t" (tab).
        // Rows are joined with "\n" (newline).
        // Geometry helpers (collectTextSegments, selectionRects) MUST mirror
        // this exact traversal order and separators.
        var allRows: [[[InlineRun]]] = [t.header]
        allRows.append(contentsOf: t.rows)
        let rowTexts = allRows.map { row in
            row.map { textForRuns($0) }.joined(separator: "\t")
        }
        return rowTexts.joined(separator: "\n")

    case .codeBlock(let cb):
        // CONSISTENCY CONTRACT for code blocks:
        // Source lines are joined with "\n" (newline).
        // Geometry helpers compute absolute UTF-16 offsets for each code-line
        // frame using the SAME order and separator.
        return cb.lines.joined(separator: "\n")

    case .image(let attachment):
        // INDEX SPACE CONTRACT: a block image occupies `alt.utf16.count` UTF-16 units
        // in the flattened text space. `selectionRects` maps the entire alt span to the
        // image rect atomically, and `copyText` returns the alt string.
        // If alt is empty, the image still occupies 0 units (i.e. the "\n" separator
        // between adjacent blocks is the only contribution of that block position).
        return attachment.alt

    case .thematicBreak:
        return ""
    }
}

func textForRuns(_ runs: [InlineRun]) -> String {
    var result = ""
    for run in runs {
        switch run {
        case .text(let s, _):
            result += s
        case .link(let innerRuns, _):
            result += textForRuns(innerRuns)
        case .inlineImage:
            // INDEX SPACE CONTRACT: must return exactly 1 UTF-16 unit to match the
            // single U+FFFC placeholder character inserted by buildAttributedString.
            result += "\u{FFFC}"
        case .lineBreak(let hard):
            result += hard ? "\n" : "\u{2028}"
        }
    }
    return result
}
