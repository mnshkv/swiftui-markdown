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
///   - `.inlineImage` → (nothing)
/// - All other block types contribute an empty string (zero-length placeholder).
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
    case .list, .quote, .table, .codeBlock, .image, .thematicBreak:
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
            break
        case .lineBreak(let hard):
            result += hard ? "\n" : "\u{2028}"
        }
    }
    return result
}
