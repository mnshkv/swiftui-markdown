// Emphasis/strikethrough resolution support (Wave 7+).
//
// At this wave: the delimiter-token model, char-aware flanking classification,
// and an adjacent-text coalescing pass. The canonical `process_emphasis`
// pairing algorithm is a later task (Wave 8).

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
