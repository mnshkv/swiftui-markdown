import CoreText
import CoreGraphics

/// Custom CFAttributedString key carrying a per-run pill background colour.
/// Read back at draw time by `DocumentRenderer` to fill a rounded background.
/// `nonisolated(unsafe)`: `CFString` is not `Sendable`, but this value is an
/// immutable string literal never mutated after initialization, so sharing it
/// across threads is safe.
nonisolated(unsafe) let markedBackgroundAttributeName = "MarkedBackgroundColor" as CFString

// MARK: - Font helper (Wave 0)

func ctFont(for style: TextStyle) -> CTFont {
    var traits: CTFontSymbolicTraits = []
    if style.isBold { traits.insert(.traitBold) }
    if style.isItalic { traits.insert(.traitItalic) }
    if style.isMonospace { traits.insert(.traitMonoSpace) }
    // Clamp to 1pt minimum — CTFontCreateUIFontForLanguage returns nil for zero/negative sizes,
    // which would crash the force-unwrap. A caller-supplied fontSize of 0 or negative is treated
    // as 1pt so layout remains usable rather than crashing.
    let size = max(style.fontSize, 1)
    let base: CTFont = style.isMonospace
        ? CTFontCreateWithName("Menlo" as CFString, size, nil)
        : CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    return CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, traits) ?? base
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
            var attrs: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: style.color
            ]
            if let bg = style.background {
                attrs[markedBackgroundAttributeName] = bg
            }
            let len = CFAttributedStringGetLength(attrStr)
            CFAttributedStringReplaceString(attrStr, CFRangeMake(len, 0), string as CFString)
            let newLen = CFAttributedStringGetLength(attrStr)
            CFAttributedStringSetAttributes(attrStr, CFRangeMake(len, newLen - len),
                                            attrs as CFDictionary, true)

        case .link(let innerRuns, _):
            appendRuns(innerRuns, into: attrStr, lastStyle: &lastStyle)

        case .inlineImage(let attachment):
            // Insert a single U+FFFC OBJECT REPLACEMENT CHARACTER as a placeholder.
            // A CTRunDelegate is attached so CoreText reserves the correct ascent/descent/width
            // for the image in the line — this makes the line height grow to fit the image.
            //
            // INDEX SPACE CONTRACT: the placeholder is ONE UTF-16 code unit (U+FFFC is in BMP),
            // so `buildAttributedString` inserts exactly 1 UTF-16 unit per `.inlineImage` run.
            // `textForRuns` must return a string of the same UTF-16 length (1) for the same run
            // to keep the global offset space consistent. See TextPosition.swift.
            let placeholder = "\u{FFFC}"
            let placeholderLen = 1  // U+FFFC is a single UTF-16 unit

            // Determine image display dimensions.
            // We use intrinsicSize as-is (no line-height scaling for now).
            let imgSize = (attachment.intrinsicSize.width > 0 && attachment.intrinsicSize.height > 0)
                ? attachment.intrinsicSize
                : CGSize(width: lastStyle.fontSize, height: lastStyle.fontSize)

            // Build CTRunDelegate callbacks.
            // The context is a heap-allocated box holding the image metrics so the
            // closure captures are lifetime-safe for the CTRunDelegate.
            final class ImageMetrics: @unchecked Sendable {
                let width: CGFloat
                let ascent: CGFloat
                let descent: CGFloat
                init(width: CGFloat, ascent: CGFloat, descent: CGFloat) {
                    self.width = width; self.ascent = ascent; self.descent = descent
                }
            }
            // Split total height into ascent (above baseline) = 80%, descent = 20%.
            let imgAscent  = imgSize.height * 0.80
            let imgDescent = imgSize.height * 0.20
            let metrics = ImageMetrics(width: imgSize.width, ascent: imgAscent, descent: imgDescent)
            let metricsPtr = Unmanaged.passRetained(metrics).toOpaque()

            var callbacks = CTRunDelegateCallbacks(
                version: kCTRunDelegateCurrentVersion,
                dealloc: { ptr in
                    Unmanaged<ImageMetrics>.fromOpaque(ptr).release()
                },
                getAscent: { ptr -> CGFloat in
                    Unmanaged<ImageMetrics>.fromOpaque(ptr).takeUnretainedValue().ascent
                },
                getDescent: { ptr -> CGFloat in
                    Unmanaged<ImageMetrics>.fromOpaque(ptr).takeUnretainedValue().descent
                },
                getWidth: { ptr -> CGFloat in
                    Unmanaged<ImageMetrics>.fromOpaque(ptr).takeUnretainedValue().width
                }
            )

            guard let delegate = CTRunDelegateCreate(&callbacks, metricsPtr) else {
                Unmanaged<ImageMetrics>.fromOpaque(metricsPtr).release()
                break
            }

            let insertPos = CFAttributedStringGetLength(attrStr)
            CFAttributedStringReplaceString(attrStr, CFRangeMake(insertPos, 0), placeholder as CFString)

            // Apply the run delegate (and a font for fallback) to the placeholder character.
            let font = ctFont(for: lastStyle)
            let imgAttrs: [CFString: Any] = [
                kCTRunDelegateAttributeName: delegate,
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: lastStyle.color
            ]
            // clearOtherAttributes = true: the run delegate must apply to ONLY the
            // placeholder. Text inserted afterwards inherits the preceding char's
            // attributes, so every text/break run uses clearOtherAttributes = true to
            // drop any inherited delegate — otherwise CoreText would size the following
            // glyphs to the image width.
            CFAttributedStringSetAttributes(
                attrStr,
                CFRangeMake(insertPos, placeholderLen),
                imgAttrs as CFDictionary,
                true
            )

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
                                            attrs as CFDictionary, true)
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

// MARK: - Table layout

/// Horizontal padding applied inside each table cell (left and right).
let tableCellPaddingH: CGFloat = 8

/// Vertical padding applied inside each table cell (top and bottom).
let tableCellPaddingV: CGFloat = 4

/// Minimum width for any table column.
let tableColumnMinWidth: CGFloat = 20

/// Thickness of table border lines.
let tableBorderThickness: CGFloat = 1

/// Measures the intrinsic single-line typographic width of a set of inline runs.
private func singleLineWidth(for runs: [InlineRun]) -> CGFloat {
    let attrStr = buildAttributedString(from: runs)
    let totalChars = CFAttributedStringGetLength(attrStr)
    guard totalChars > 0 else { return 0 }
    let typesetter = CTTypesetterCreateWithAttributedString(attrStr)
    let ctLine = CTTypesetterCreateLine(typesetter, CFRangeMake(0, totalChars))
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let w = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))
    return w
}

/// Returns the column widths for a table, distributed within `available` points.
///
/// - Intrinsic width per column = max single-line width of any cell in that column + 2 * tableCellPaddingH.
/// - If the sum of intrinsic widths exceeds `available`, columns are scaled down proportionally
///   (each clamped to `tableColumnMinWidth`).
/// - Returns an empty array if the table has no columns.
public func tableColumnWidths(_ t: Table, available: CGFloat) -> [CGFloat] {
    // Determine column count = max(header.count, max(row.count) for all rows)
    var colCount = t.header.count
    for row in t.rows { colCount = max(colCount, row.count) }
    guard colCount > 0 else { return [] }

    // Compute intrinsic width per column (max over all cells in that column)
    var intrinsic = [CGFloat](repeating: 0, count: colCount)
    // Measure header cells
    for (col, cell) in t.header.enumerated() {
        let w = singleLineWidth(for: cell) + 2 * tableCellPaddingH
        intrinsic[col] = max(intrinsic[col], w)
    }
    // Measure body row cells
    for row in t.rows {
        for (col, cell) in row.enumerated() {
            let w = singleLineWidth(for: cell) + 2 * tableCellPaddingH
            intrinsic[col] = max(intrinsic[col], w)
        }
    }

    let sum = intrinsic.reduce(0, +)
    if sum <= available {
        return intrinsic
    }

    // Scale down proportionally, clamping to minimum
    let scale = available / sum
    var result = intrinsic.map { max($0 * scale, tableColumnMinWidth) }

    // After clamping, some columns may be wider than scaled; re-normalize if needed
    let newSum = result.reduce(0, +)
    if newSum > available + 0.5 {
        // Distribute excess evenly (best-effort; never go below minimum)
        let excess = newSum - available
        let nonMinCount = result.filter { $0 > tableColumnMinWidth + 0.5 }.count
        if nonMinCount > 0 {
            let cut = excess / CGFloat(nonMinCount)
            result = result.map { w in
                w > tableColumnMinWidth + 0.5 ? max(w - cut, tableColumnMinWidth) : w
            }
        }
    }

    return result
}

/// Lays out a single table cell's runs into multiple lines within `width`, starting at `origin`.
/// Returns the array of `LineFrame` values and the total height of the cell.
private func layoutCellRuns(
    _ runs: [InlineRun],
    width: CGFloat,
    origin: CGPoint,
    alignment: TextAlignment
) -> (lines: [LineFrame], height: CGFloat) {
    guard !runs.isEmpty else { return ([], 0) }
    let attrStr = buildAttributedString(from: runs)
    let totalChars = CFAttributedStringGetLength(attrStr)
    guard totalChars > 0 else { return ([], 0) }

    let typesetter = CTTypesetterCreateWithAttributedString(attrStr)
    var lineFrames: [LineFrame] = []
    var charIndex = 0
    var cursorY = origin.y

    while charIndex < totalChars {
        let count = CTTypesetterSuggestLineBreak(typesetter, charIndex, Double(width))
        if count == 0 { break }

        let ctLine = CTTypesetterCreateLine(typesetter, CFRangeMake(charIndex, count))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let lineW = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))

        // Compute x offset based on alignment
        let xOffset: CGFloat
        switch alignment {
        case .leading, .justified:
            xOffset = 0
        case .center:
            xOffset = max(0, (width - lineW) / 2)
        case .trailing:
            xOffset = max(0, width - lineW)
        }

        let lineOrigin = CGPoint(x: origin.x + xOffset, y: cursorY)
        let lineSize = CGSize(width: lineW, height: ascent + descent)
        lineFrames.append(LineFrame(
            origin: lineOrigin,
            size: lineSize,
            ascent: ascent,
            descent: descent,
            ctLine: ctLine,
            charRange: charIndex..<(charIndex + count)
        ))

        cursorY += ascent + descent
        charIndex += count
    }

    return (lineFrames, cursorY - origin.y)
}

/// Lays out a `Table` block starting at `origin`.
func layoutTable(_ t: Table, width: CGFloat, origin: CGPoint) -> BlockFrame {
    let columnWidths = tableColumnWidths(t, available: width)
    let colCount = columnWidths.count

    guard colCount > 0 else {
        let rect = CGRect(x: origin.x, y: origin.y, width: width, height: 0)
        return .table(rect: rect, columnX: [], rowYs: [origin.y], cellLines: [], borders: [])
    }

    // Build column x positions
    var columnX: [CGFloat] = []
    var xCursor = origin.x
    for w in columnWidths {
        columnX.append(xCursor + tableCellPaddingH)
        xCursor += w
    }

    // All rows = [header] + rows
    var allRows: [[[InlineRun]]] = [t.header]
    allRows.append(contentsOf: t.rows)

    var rowYs: [CGFloat] = [origin.y]
    var allCellLines: [[[LineFrame]]] = []
    var cursorY = origin.y

    for row in allRows {
        var rowMaxHeight: CGFloat = 0
        var rowCellLines: [[LineFrame]] = []

        for col in 0..<colCount {
            let cellRuns = col < row.count ? row[col] : []
            let colAlignment = col < t.alignments.count ? t.alignments[col] : .leading
            let cellWidth = columnWidths[col] - 2 * tableCellPaddingH
            let cellOrigin = CGPoint(x: columnX[col], y: cursorY + tableCellPaddingV)
            let (lines, cellContentH) = layoutCellRuns(
                cellRuns,
                width: max(cellWidth, 1),
                origin: cellOrigin,
                alignment: colAlignment
            )
            rowCellLines.append(lines)
            rowMaxHeight = max(rowMaxHeight, cellContentH + 2 * tableCellPaddingV)
        }

        allCellLines.append(rowCellLines)
        cursorY += rowMaxHeight
        rowYs.append(cursorY)
    }

    // Build border rects
    var borders: [CGRect] = []

    // The table box hugs its columns rather than stretching to the full available
    // width. tableColumnWidths already fits the columns within `width`; using their
    // sum keeps the horizontal borders aligned with the right column edge instead of
    // leaving an empty boxed area on the right.
    let columnsWidth = columnWidths.reduce(0, +)

    // Horizontal row dividers (lines between rows including top, bottom, and after-header)
    let tableRight = origin.x + columnsWidth
    for y in rowYs {
        borders.append(CGRect(x: origin.x, y: y, width: tableRight - origin.x, height: tableBorderThickness))
    }

    // Vertical column dividers (left edge + between columns)
    var xDiv = origin.x
    let tableBottom = rowYs.last ?? origin.y
    let tableHeight = tableBottom - origin.y
    for (i, w) in columnWidths.enumerated() {
        borders.append(CGRect(x: xDiv, y: origin.y, width: tableBorderThickness, height: tableHeight))
        if i == columnWidths.count - 1 {
            // Right edge
            borders.append(CGRect(x: xDiv + w, y: origin.y, width: tableBorderThickness, height: tableHeight))
        }
        xDiv += w
    }

    let tableRect = CGRect(x: origin.x, y: origin.y, width: columnsWidth, height: tableHeight)
    return .table(rect: tableRect, columnX: columnX, rowYs: rowYs, cellLines: allCellLines, borders: borders)
}

// MARK: - Code block layout

/// Padding around code block content (inside the box).
let codePaddingH: CGFloat = 12
let codePaddingV: CGFloat = 8

/// Gap between the language label and the code box.
let codeLabelGap: CGFloat = 4

/// Lays out a `CodeBlock` starting at `origin`.
func layoutCodeBlock(_ cb: CodeBlock, width: CGFloat, origin: CGPoint) -> BlockFrame {
    var cursorY = origin.y

    // Optional language label
    var langLabelFrame: LineFrame? = nil
    if let lang = cb.language, !lang.isEmpty {
        let labelStyle = TextStyle(fontSize: 11, isMonospace: false,
                                   color: CGColor(gray: 0.4, alpha: 1))
        let labelAttr = buildAttributedString(from: [.text(lang, labelStyle)])
        let labelChars = CFAttributedStringGetLength(labelAttr)
        if labelChars > 0 {
            let ts = CTTypesetterCreateWithAttributedString(labelAttr)
            let ctLine = CTTypesetterCreateLine(ts, CFRangeMake(0, labelChars))
            var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
            let lw = CGFloat(CTLineGetTypographicBounds(ctLine, &asc, &desc, &lead))
            let lf = LineFrame(
                origin: CGPoint(x: origin.x, y: cursorY),
                size: CGSize(width: lw, height: asc + desc),
                ascent: asc, descent: desc,
                ctLine: ctLine,
                charRange: 0..<labelChars
            )
            langLabelFrame = lf
            cursorY += asc + desc + codeLabelGap
        }
    }

    // Content area starts here
    let boxTop = cursorY
    let contentX = origin.x + codePaddingH
    let contentWidth = max(width - 2 * codePaddingH, 1)
    cursorY += codePaddingV

    // Lay out each source line (wrap if too long)
    var lineFrames: [LineFrame] = []

    if cb.lines.isEmpty {
        // Empty code block: just the padding
        cursorY += codePaddingV
    } else {
        for sourceLine in cb.lines {
            let attrStr = buildAttributedString(from: [.text(sourceLine, cb.style)])
            let totalChars = CFAttributedStringGetLength(attrStr)

            if totalChars == 0 {
                // Blank line — produce a zero-height spacer frame
                // We need to measure a space for the line height
                let spaceAttr = buildAttributedString(from: [.text(" ", cb.style)])
                let spaceChars = CFAttributedStringGetLength(spaceAttr)
                let spaceTypesetter = CTTypesetterCreateWithAttributedString(spaceAttr)
                let spaceLine = CTTypesetterCreateLine(spaceTypesetter, CFRangeMake(0, spaceChars))
                var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
                _ = CTLineGetTypographicBounds(spaceLine, &asc, &desc, &lead)
                let lf = LineFrame(
                    origin: CGPoint(x: contentX, y: cursorY),
                    size: CGSize(width: 0, height: asc + desc),
                    ascent: asc, descent: desc,
                    ctLine: spaceLine,
                    charRange: 0..<0
                )
                lineFrames.append(lf)
                cursorY += asc + desc
                continue
            }

            let typesetter = CTTypesetterCreateWithAttributedString(attrStr)
            var charIndex = 0
            while charIndex < totalChars {
                let count = CTTypesetterSuggestLineBreak(typesetter, charIndex, Double(contentWidth))
                if count == 0 { break }
                let ctLine = CTTypesetterCreateLine(typesetter, CFRangeMake(charIndex, count))
                var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
                let lw = CGFloat(CTLineGetTypographicBounds(ctLine, &asc, &desc, &lead))
                let lf = LineFrame(
                    origin: CGPoint(x: contentX, y: cursorY),
                    size: CGSize(width: lw, height: asc + desc),
                    ascent: asc, descent: desc,
                    ctLine: ctLine,
                    charRange: charIndex..<(charIndex + count)
                )
                lineFrames.append(lf)
                cursorY += asc + desc
                charIndex += count
            }
        }
        cursorY += codePaddingV
    }

    let boxBottom = cursorY
    let boxRect = CGRect(x: origin.x, y: boxTop, width: width, height: boxBottom - boxTop)
    let totalRect = CGRect(x: origin.x, y: origin.y, width: width, height: cursorY - origin.y)

    return .code(rect: totalRect, box: boxRect, lines: lineFrames, languageLabel: langLabelFrame)
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

// MARK: - Block image layout

/// Placeholder size used when `intrinsicSize` is zero (width == 0 or height == 0).
let imagePlaceholderSize = CGSize(width: 200, height: 150)

/// Lays out a block `ImageAttachment` into a `BlockFrame.image`.
///
/// - The image rect is scaled to fit `width` while preserving aspect ratio.
/// - If `intrinsicSize` is zero in either dimension, `imagePlaceholderSize` is used instead.
/// - The image is NOT loaded here (layout is pure/synchronous).
func layoutImage(_ attachment: ImageAttachment, width: CGFloat, origin: CGPoint) -> BlockFrame {
    let intrinsic = (attachment.intrinsicSize.width > 0 && attachment.intrinsicSize.height > 0)
        ? attachment.intrinsicSize
        : imagePlaceholderSize

    // Scale down to fit width (preserve aspect ratio); never scale up.
    let scale = intrinsic.width > width ? width / intrinsic.width : 1.0
    let imgWidth = intrinsic.width * scale
    let imgHeight = intrinsic.height * scale

    let rect = CGRect(x: origin.x, y: origin.y, width: imgWidth, height: imgHeight)
    return .image(rect: rect, attachment: attachment)
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
        let width = max(width, 1)
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
                let frame = layoutImage(attachment, width: width, origin: CGPoint(x: origin.x, y: cursorY))
                blockFrames.append(frame)
                if case .image(let rect, _) = frame {
                    cursorY = rect.maxY
                    contentHeight = rect.maxY - origin.y
                }

            case .codeBlock(let cb):
                let codeFrame = layoutCodeBlock(cb, width: width, origin: CGPoint(x: origin.x, y: cursorY))
                blockFrames.append(codeFrame)
                if case .code(let rect, _, _, _) = codeFrame {
                    cursorY = rect.maxY
                    contentHeight = rect.maxY - origin.y
                }

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

            case .table(let t):
                let tableFrame = layoutTable(t, width: width, origin: CGPoint(x: origin.x, y: cursorY))
                blockFrames.append(tableFrame)
                if case .table(let rect, _, _, _, _) = tableFrame {
                    cursorY = rect.maxY
                    contentHeight = rect.maxY - origin.y
                }
            }
        }

        return DocumentLayout(
            blocks: blockFrames,
            // contentSize.height is the height of laid-out content (not the maxY).
            contentSize: CGSize(width: width, height: contentHeight)
        )
    }
}
