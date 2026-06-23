import Foundation
import CoreGraphics

// MARK: - Word selection helper (pure, unit-testable seam for double-tap)

/// Returns a `TextRange` covering the word at `point` within `layout` / `doc`.
///
/// This is the pure seam extracted for unit testing of double-tap selection.
/// The gesture wiring itself lives in `TextEngineView` (platform code).
///
/// Steps:
///   1. Hit-test `point` → `TextPosition` (via `position(at:in:doc:)`).
///   2. Expand that position to a word boundary via `wordRange(at:doc:)`.
///
/// A `nil` return means the point didn't land in any text (position == totalUTF16,
/// or the word range at that position is zero-length).
public func wordSelection(at point: CGPoint, layout: DocumentLayout, doc: TextDocument) -> TextRange {
    let pos = position(at: point, in: layout, doc: doc)
    return wordRange(at: pos, doc: doc)
}

// MARK: - Copy text

/// Returns the plain-text substring of `doc` covered by `range`.
///
/// Indices are UTF-16 offsets into `flattenedText(doc)`. Out-of-bounds indices are clamped.
/// An empty range returns `""`.
public func copyText(for range: TextRange, doc: TextDocument) -> String {
    let flat = flattenedText(doc)
    let utf16 = flat.utf16
    let total = utf16.count

    let start = max(0, min(range.start.index, total))
    let end = max(0, min(range.end.index, total))
    guard start < end else { return "" }

    let startIdx = utf16.index(utf16.startIndex, offsetBy: start)
    let endIdx = utf16.index(utf16.startIndex, offsetBy: end)
    return String(utf16[startIdx..<endIdx]) ?? ""
}

// MARK: - Word range

/// Returns a `TextRange` covering the word that contains `position`.
///
/// Uses `String.enumerateSubstrings(options: .byWords)` to locate the word.
/// If no word is found at the position (e.g. the position is on whitespace or out of bounds),
/// returns a zero-length range at the (clamped) position.
public func wordRange(at position: TextPosition, doc: TextDocument) -> TextRange {
    let flat = flattenedText(doc)
    let utf16 = flat.utf16
    let total = utf16.count

    // Clamp index
    let clampedIndex = max(0, min(position.index, total))
    let zeroLength = TextRange(start: TextPosition(index: clampedIndex), end: TextPosition(index: clampedIndex))

    guard clampedIndex < total else { return zeroLength }

    // Convert UTF-16 offset to String.Index
    let targetUTF16Idx = utf16.index(utf16.startIndex, offsetBy: clampedIndex)
    // Convert to Character-level index for enumerateSubstrings.
    // If the UTF-16 index lands mid-surrogate-pair, samePosition returns nil —
    // return a zero-length range at the clamped position rather than silently
    // falling back to position 0 and returning the wrong word.
    guard let targetIdx = targetUTF16Idx.samePosition(in: flat) else { return zeroLength }

    var result: TextRange? = nil
    flat.enumerateSubstrings(in: flat.startIndex..., options: .byWords) { _, substringRange, _, stop in
        // Check if targetIdx falls within this word's range
        if substringRange.lowerBound <= targetIdx && targetIdx < substringRange.upperBound {
            // Convert substring bounds to UTF-16 offsets
            let wordStart = flat.utf16.distance(from: flat.utf16.startIndex,
                                                 to: substringRange.lowerBound.samePosition(in: flat.utf16)
                                                    ?? flat.utf16.startIndex)
            let wordEnd = flat.utf16.distance(from: flat.utf16.startIndex,
                                               to: substringRange.upperBound.samePosition(in: flat.utf16)
                                                  ?? flat.utf16.startIndex)
            result = TextRange(start: TextPosition(index: wordStart), end: TextPosition(index: wordEnd))
            stop = true
        }
    }

    return result ?? zeroLength
}
