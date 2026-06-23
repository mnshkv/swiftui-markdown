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

/// One node in the working doubly-linked list used by `processEmphasis`:
/// either resolved inline content or a still-active delimiter run.
private final class EmphNode {
    enum Kind {
        case inline(MarkdownInline)
        case delim(char: Character, count: Int, origCount: Int, canOpen: Bool, canClose: Bool)
    }
    var kind: Kind
    var prev: EmphNode?
    var next: EmphNode?
    init(_ kind: Kind) { self.kind = kind }
}

private func emphNodeInlines(_ node: EmphNode) -> [MarkdownInline] {
    switch node.kind {
    case .inline(let inline):
        return [inline]
    case .delim(let char, let count, _, _, _):
        return count > 0 ? [.text(String(repeating: char, count: count))] : []
    }
}

/// Pairs `*`/`_` emphasis delimiters in a token stream into `.emphasis`/`.strong`
/// nodes via the canonical CommonMark `process_emphasis` (delimiter list,
/// `openers_bottom`, rule of 3). Unpaired delimiters flatten to literal text;
/// `~` delimiters are left untouched for the strikethrough pass.
func processEmphasis(_ tokens: [InlineToken]) -> [MarkdownInline] {
    var head: EmphNode?
    var tail: EmphNode?
    for token in tokens {
        let node: EmphNode
        switch token {
        case .literal(let inline):
            node = EmphNode(.inline(inline))
        case .delim(let char, let count, let origCount, let canOpen, let canClose):
            node = EmphNode(.delim(char: char, count: count, origCount: origCount, canOpen: canOpen, canClose: canClose))
        }
        node.prev = tail
        tail?.next = node
        if head == nil { head = node }
        tail = node
    }

    var openersBottom: [String: EmphNode?] = [:]
    var closer = head
    while let cur = closer {
        guard case .delim(let cchar, let ccount, let corig, let ccanOpen, let ccanClose) = cur.kind,
              ccanClose, cchar == "*" || cchar == "_" || cchar == "~" else {
            closer = cur.next
            continue
        }
        let obKey = "\(cchar)\(ccanOpen)\(corig % 3)"
        let floor: EmphNode? = openersBottom[obKey].flatMap { $0 } // flatten EmphNode?? -> EmphNode?

        var opener = cur.prev
        var matched: EmphNode?
        while let op = opener, op !== floor {
            if case .delim(let ochar, let ocount, let oorig, let ocanOpen, _) = op.kind, ocanOpen, ochar == cchar {
                if cchar == "~" {
                    // GFM strikethrough: pair only exact length-2 runs (v1).
                    if ccount == 2, ocount == 2 { matched = op; break }
                } else {
                    let oddMatch = (ccanOpen || isCanClose(op))
                        && (corig + oorig) % 3 == 0
                        && !(corig % 3 == 0 && oorig % 3 == 0)
                    if !oddMatch { matched = op; break }
                }
            }
            opener = op.prev
        }

        guard let op = matched,
              case .delim(let ochar, let ocount, let oorig, let ocanOpen, let ocanClose) = op.kind else {
            openersBottom[obKey] = cur.prev
            if !ccanOpen { cur.kind = .inline(.text(String(repeating: cchar, count: ccount))) }
            closer = cur.next
            continue
        }

        let strike = cchar == "~"
        let strong = !strike && ocount >= 2 && ccount >= 2
        let use = strike || strong ? 2 : 1

        var inner: [MarkdownInline] = []
        var between = op.next
        while let node = between, node !== cur {
            inner.append(contentsOf: emphNodeInlines(node))
            between = node.next
        }
        let wrappedInline: MarkdownInline = strike ? .strikethrough(inner) : (strong ? .strong(inner) : .emphasis(inner))
        let wrapped = EmphNode(.inline(wrappedInline))
        op.next = wrapped; wrapped.prev = op
        wrapped.next = cur; cur.prev = wrapped

        if ocount - use > 0 {
            op.kind = .delim(char: ochar, count: ocount - use, origCount: oorig, canOpen: ocanOpen, canClose: ocanClose)
        } else {
            let p = op.prev
            wrapped.prev = p
            if let p { p.next = wrapped } else { head = wrapped }
        }

        if ccount - use > 0 {
            cur.kind = .delim(char: cchar, count: ccount - use, origCount: corig, canOpen: ccanOpen, canClose: ccanClose)
            // closer keeps remaining length — re-loop to pair it again
        } else {
            let nx = cur.next
            wrapped.next = nx
            nx?.prev = wrapped
            closer = nx
        }
    }

    var result: [MarkdownInline] = []
    var node = head
    while let n = node {
        result.append(contentsOf: emphNodeInlines(n))
        node = n.next
    }
    return result
}

/// Whether an `EmphNode` delimiter can close (used inside the rule-of-3 check).
private func isCanClose(_ node: EmphNode) -> Bool {
    if case .delim(_, _, _, _, let canClose) = node.kind { return canClose }
    return false
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
