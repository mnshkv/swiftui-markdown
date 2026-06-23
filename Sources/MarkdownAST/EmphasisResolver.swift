// Emphasis/strikethrough resolution support (Wave 7+).
//
// At this wave: the delimiter-token model, char-aware flanking classification,
// and an adjacent-text coalescing pass. The canonical `process_emphasis`
// pairing algorithm is a later task (Wave 8).

/// Merges consecutive `.text` nodes into one, recursing into the children of
/// emphasis/strong/strikethrough/link (K6).
func coalesceText(_ inlines: [MarkdownInline]) -> [MarkdownInline] {
    var result: [MarkdownInline] = []
    for node in inlines {
        let coalesced = coalesceChildren(node)
        if case .text(let next) = coalesced, case .text(let prev)? = result.last {
            result[result.count - 1] = .text(prev + next)
        } else {
            result.append(coalesced)
        }
    }
    return result
}

/// Recurses `coalesceText` into the inline children of container nodes.
private func coalesceChildren(_ node: MarkdownInline) -> MarkdownInline {
    switch node {
    case .emphasis(let c): return .emphasis(coalesceText(c))
    case .strong(let c): return .strong(coalesceText(c))
    case .strikethrough(let c): return .strikethrough(coalesceText(c))
    case .link(let destination, let title, let c):
        return .link(destination: destination, title: title, content: coalesceText(c))
    default:
        return node
    }
}

/// A token in the inline emphasis pipeline: either a resolved inline node, or a
/// run of emphasis/strikethrough delimiters awaiting pairing (Wave 8).
enum InlineToken: Equatable {
    case literal(MarkdownInline)
    case delim(char: Character, count: Int, origCount: Int, canOpen: Bool, canClose: Bool)
}

/// CommonMark "punctuation": ASCII punctuation, or a Unicode punctuation/symbol
/// character. (Swift's `isPunctuation` alone misses ASCII symbols like `~`.)
func isCommonMarkPunctuation(_ c: Character?) -> Bool {
    guard let c else { return false }
    if c.isASCII { return asciiPunctuation.contains(c) }
    return c.isPunctuation || c.isSymbol
}

/// The 32 ASCII punctuation characters (CommonMark §2.1).
private let asciiPunctuation: Set<Character> = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")

/// Classifies an emphasis/strikethrough delimiter run by CommonMark flanking
/// rules. `*`/`~` use plain left/right-flanking; `_` adds the intraword rule
/// (open only when not right-flanking or preceded by punctuation, and the
/// mirror for closing) so `a_b_c` does not emphasize (K7).
func classifyFlanking(char: Character, before: Character?, after: Character?) -> (canOpen: Bool, canClose: Bool) {
    let beforeWS = before == nil || before!.isWhitespace
    let afterWS = after == nil || after!.isWhitespace
    let beforeP = isCommonMarkPunctuation(before)
    let afterP = isCommonMarkPunctuation(after)
    let leftFlanking = !afterWS && (!afterP || beforeWS || beforeP)
    let rightFlanking = !beforeWS && (!beforeP || afterWS || afterP)
    switch char {
    case "_":
        return (leftFlanking && (!rightFlanking || beforeP),
                rightFlanking && (!leftFlanking || afterP))
    default: // "*", "~"
        return (leftFlanking, rightFlanking)
    }
}
