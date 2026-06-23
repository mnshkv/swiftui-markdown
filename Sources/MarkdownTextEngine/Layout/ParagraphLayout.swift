import CoreText
import CoreGraphics

// MARK: - Font helper (Wave 0)

func ctFont(for style: TextStyle) -> CTFont {
    var traits: CTFontSymbolicTraits = []
    if style.isBold { traits.insert(.traitBold) }
    if style.isItalic { traits.insert(.traitItalic) }
    if style.isMonospace { traits.insert(.traitMonoSpace) }
    let base = style.isMonospace
        ? CTFontCreateWithName("Menlo" as CFString, style.fontSize, nil)
        : CTFontCreateUIFontForLanguage(.system, style.fontSize, nil)!
    return CTFontCreateCopyWithSymbolicTraits(base, style.fontSize, nil, traits, traits) ?? base
}

// MARK: - Attributed string builder

/// Converts `InlineRun` tree into a `CFMutableAttributedString`.
/// Every character — including line-break characters — carries explicit font and color
/// attributes so CoreText never falls back to a default system font.
func buildAttributedString(from runs: [InlineRun]) -> CFMutableAttributedString {
    let attrStr = CFAttributedStringCreateMutable(nil, 0)!
    var lastStyle = _defaultBreakStyle
    appendRuns(runs, into: attrStr, lastStyle: &lastStyle)
    return attrStr
}

/// Default style used when a `.lineBreak` run appears before any `.text` run.
private let _defaultBreakStyle = TextStyle(fontSize: 17, color: CGColor(gray: 0, alpha: 1))

private func appendRuns(_ runs: [InlineRun], into attrStr: CFMutableAttributedString,
                        lastStyle: inout TextStyle) {
    for run in runs {
        switch run {
        case .text(let string, let style):
            lastStyle = style
            let font = ctFont(for: style)
            let attrs: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: style.color
            ]
            let len = CFAttributedStringGetLength(attrStr)
            CFAttributedStringReplaceString(attrStr, CFRangeMake(len, 0), string as CFString)
            let newLen = CFAttributedStringGetLength(attrStr)
            CFAttributedStringSetAttributes(attrStr, CFRangeMake(len, newLen - len),
                                            attrs as CFDictionary, false)

        case .link(let innerRuns, _):
            appendRuns(innerRuns, into: attrStr, lastStyle: &lastStyle)

        case .inlineImage:
            // Placeholder: images not rendered in this wave
            break

        case .lineBreak(let hard):
            // Apply the most recent text style (or the default if no text seen yet)
            // so CoreText does not fall back to a system default font for the break glyph.
            let breakChar = hard ? "\n" : "\u{2028}" // LINE SEPARATOR for soft break
            let style = lastStyle
            let font = ctFont(for: style)
            let attrs: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: style.color
            ]
            let len = CFAttributedStringGetLength(attrStr)
            CFAttributedStringReplaceString(attrStr, CFRangeMake(len, 0), breakChar as CFString)
            let newLen = CFAttributedStringGetLength(attrStr)
            CFAttributedStringSetAttributes(attrStr, CFRangeMake(len, newLen - len),
                                            attrs as CFDictionary, false)
        }
    }
}

// MARK: - Paragraph layout

/// Lays out a single `Paragraph` into a `BlockFrame.text`, starting at `origin`.
/// Returns the frame and advances `origin.y` past the block (including spacingAfter).
public func layoutParagraph(_ p: Paragraph, width: CGFloat, origin: CGPoint) -> BlockFrame {
    let attrStr = buildAttributedString(from: p.runs)
    let totalChars = CFAttributedStringGetLength(attrStr)
    let typesetter = CTTypesetterCreateWithAttributedString(attrStr)

    let style = p.style
    let lineSpacing = style.lineSpacing
    let leadingIndent = style.leadingIndent
    let lineWidth = width - leadingIndent

    var lineFrames: [LineFrame] = []
    var charIndex = 0
    var cursorY = origin.y  // current top of the line

    while charIndex < totalChars {
        // How many characters fit on this line?
        let count = CTTypesetterSuggestLineBreak(typesetter, charIndex, Double(lineWidth))
        if count == 0 { break } // safety: avoid infinite loop

        let ctLine = CTTypesetterCreateLine(typesetter, CFRangeMake(charIndex, count))

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth_ = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))

        // Baseline is at cursorY + ascent
        let lineOrigin = CGPoint(x: origin.x + leadingIndent, y: cursorY)
        let lineSize = CGSize(width: lineWidth_, height: ascent + descent)

        lineFrames.append(LineFrame(
            origin: lineOrigin,
            size: lineSize,
            ascent: ascent,
            descent: descent,
            ctLine: ctLine,
            charRange: charIndex..<(charIndex + count)
        ))

        cursorY += ascent + descent + lineSpacing
        charIndex += count
    }

    let blockHeight = cursorY - origin.y
    let blockRect = CGRect(x: origin.x, y: origin.y, width: width, height: blockHeight)
    return .text(rect: blockRect, lines: lineFrames)
}

// MARK: - List & quote layout constants

/// Horizontal indent for list item content (from the block left edge to content start).
let listItemIndent: CGFloat = 24

/// Horizontal indent for block-quote content.
let quoteIndent: CGFloat = 16

/// Width of the block-quote left bar.
let quoteBarWidth: CGFloat = 3

/// Vertical gap between list items in loose lists.
let listItemSpacing: CGFloat = 8

// MARK: - List layout

/// Lays out a `List` block starting at `origin`.
func layoutList(_ list: List, width: CGFloat, origin: CGPoint) -> BlockFrame {
    guard !list.items.isEmpty else {
        let rect = CGRect(x: origin.x, y: origin.y, width: width, height: 0)
        return .list(rect: rect, itemLayouts: [], markerFrames: [], markerStrings: [])
    }

    let itemWidth = width - listItemIndent
    var itemLayouts: [DocumentLayout] = []
    var markerFrames: [CGRect] = []
    var markerStrings: [String] = []
    var cursorY = origin.y

    for (i, itemDoc) in list.items.enumerated() {
        // Build marker string
        let markerString: String
        switch list.marker {
        case .bullet:
            markerString = "•"
        case .ordered(let start):
            markerString = "\(start + i)."
        }
        markerStrings.append(markerString)

        // Lay out the item document at the indented x position
        let itemOrigin = CGPoint(x: origin.x + listItemIndent, y: cursorY)
        // Recursively lay out the item's content
        let itemLayout = LayoutEngine.layoutWithOrigin(itemDoc, width: itemWidth, origin: itemOrigin)
        let itemHeight = itemLayout.contentSize.height

        // Determine marker position: align with first line's baseline if available
        let markerStyle = TextStyle(fontSize: 17, color: CGColor(gray: 0, alpha: 1))
        let markerFont = ctFont(for: markerStyle)
        var markerAscent: CGFloat = 0
        var markerDescent: CGFloat = 0
        var markerLeading: CGFloat = 0
        let markerAttrStr = CFAttributedStringCreate(nil, markerString as CFString,
            [kCTFontAttributeName: markerFont] as CFDictionary)!
        let markerTypesetter = CTTypesetterCreateWithAttributedString(markerAttrStr)
        let markerCTLine = CTTypesetterCreateLine(markerTypesetter, CFRangeMake(0, CFAttributedStringGetLength(markerAttrStr)))
        let markerWidth = CGFloat(CTLineGetTypographicBounds(markerCTLine, &markerAscent, &markerDescent, &markerLeading))

        // Find first line baseline in item layout for marker placement
        var firstLineBaseline: CGFloat = cursorY + markerAscent  // fallback
        outerSearch: for block in itemLayout.blocks {
            if case .text(_, let lines) = block, let firstLine = lines.first {
                firstLineBaseline = firstLine.origin.y + firstLine.ascent
                break outerSearch
            }
        }

        // Marker rect: to the left of the indent, vertically positioned at the first line baseline
        let markerX = origin.x
        let markerTop = firstLineBaseline - markerAscent
        let markerRect = CGRect(x: markerX, y: markerTop,
                                width: markerWidth, height: markerAscent + markerDescent)
        markerFrames.append(markerRect)

        // Store the CTLine in item layout metadata — we carry it via markerFrames, markerStrings
        itemLayouts.append(itemLayout)

        cursorY += itemHeight
        if i < list.items.count - 1 {
            cursorY += list.isTight ? 0 : listItemSpacing
        }
    }

    let totalHeight = cursorY - origin.y
    let listRect = CGRect(x: origin.x, y: origin.y, width: width, height: totalHeight)
    return .list(rect: listRect, itemLayouts: itemLayouts, markerFrames: markerFrames, markerStrings: markerStrings)
}

// MARK: - Quote layout

/// Lays out a block-quote starting at `origin`.
func layoutQuote(_ innerDoc: TextDocument, width: CGFloat, origin: CGPoint) -> BlockFrame {
    let innerWidth = width - quoteIndent
    let innerOrigin = CGPoint(x: origin.x + quoteIndent, y: origin.y)
    let innerLayout = LayoutEngine.layoutWithOrigin(innerDoc, width: innerWidth, origin: innerOrigin)
    let innerHeight = innerLayout.contentSize.height

    let barRect = CGRect(x: origin.x, y: origin.y, width: quoteBarWidth, height: innerHeight)
    let quoteRect = CGRect(x: origin.x, y: origin.y, width: width, height: innerHeight)
    return .quote(rect: quoteRect, inner: innerLayout, barRect: barRect)
}

// MARK: - LayoutEngine

public enum LayoutEngine {

    /// Lays out `doc` starting at y=0, x=0. The public entry point for top-level documents.
    public static func layout(_ doc: TextDocument, width: CGFloat) -> DocumentLayout {
        layoutWithOrigin(doc, width: width, origin: .zero)
    }

    /// Lays out `doc` within a horizontal band of `width` points, with content starting at
    /// `origin` in the enclosing document's coordinate space.
    ///
    /// Used internally for recursive layout of list items and block-quotes.
    /// `contentSize.height` is the height of the laid-out content (maxY - origin.y of the last block).
    static func layoutWithOrigin(_ doc: TextDocument, width: CGFloat, origin: CGPoint) -> DocumentLayout {
        var blockFrames: [BlockFrame] = []
        var cursorY: CGFloat = origin.y
        // Tracks the maxY of the most recently appended block rect (no trailing gap).
        var contentHeight: CGFloat = 0

        for block in doc.blocks {
            switch block {
            case .paragraph(let p):
                cursorY += p.style.spacingBefore
                let blockOrigin = CGPoint(x: origin.x, y: cursorY)
                let frame = layoutParagraph(p, width: width, origin: blockOrigin)
                blockFrames.append(frame)
                if case .text(let rect, _) = frame {
                    cursorY = rect.maxY
                    contentHeight = rect.maxY - origin.y
                }
                cursorY += p.style.spacingAfter

            case .thematicBreak(let rule):
                let ruleHeight = rule.thickness
                let rect = CGRect(x: origin.x, y: cursorY, width: width, height: ruleHeight)
                blockFrames.append(.rule(rect))
                cursorY += ruleHeight
                contentHeight = cursorY - origin.y

            case .image(let attachment):
                let imgSize = attachment.intrinsicSize
                let rect = CGRect(x: origin.x, y: cursorY, width: imgSize.width, height: imgSize.height)
                blockFrames.append(.image(rect: rect, attachment: attachment))
                cursorY += imgSize.height
                contentHeight = cursorY - origin.y

            case .codeBlock:
                // Placeholder – code blocks handled in a later wave
                let rect = CGRect(x: origin.x, y: cursorY, width: width, height: 0)
                blockFrames.append(.code(rect: rect))

            case .list(let list):
                let listFrame = layoutList(list, width: width, origin: CGPoint(x: origin.x, y: cursorY))
                blockFrames.append(listFrame)
                if case .list(let rect, _, _, _) = listFrame {
                    cursorY = rect.maxY
                    contentHeight = rect.maxY - origin.y
                }

            case .quote(let innerDoc):
                let quoteFrame = layoutQuote(innerDoc, width: width, origin: CGPoint(x: origin.x, y: cursorY))
                blockFrames.append(quoteFrame)
                if case .quote(let rect, _, _) = quoteFrame {
                    cursorY = rect.maxY
                    contentHeight = rect.maxY - origin.y
                }

            case .table:
                // Placeholder – tables handled in a later wave
                let rect = CGRect(x: origin.x, y: cursorY, width: width, height: 0)
                blockFrames.append(.table(rect: rect))
            }
        }

        return DocumentLayout(
            blocks: blockFrames,
            // contentSize.height is the height of laid-out content (not the maxY).
            contentSize: CGSize(width: width, height: contentHeight)
        )
    }
}
