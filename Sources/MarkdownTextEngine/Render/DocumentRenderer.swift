import CoreText
import CoreGraphics

// NOTE: This file intentionally imports ONLY CoreText and CoreGraphics.
// It must NOT import SwiftUI, UIKit, or AppKit.
// Platform-specific code lives exclusively in Platform/.

/// Stateless drawing engine for a laid-out `DocumentLayout`.
///
/// Coordinate space: Core Graphics uses a bottom-left origin (y-up).
/// `DocumentLayout` uses a top-left origin (y-down).
/// `DocumentRenderer` performs the flip internally so callers work in
/// document / view space throughout.
public enum DocumentRenderer {

    // MARK: - Selection highlight color

    /// RGBA components for the selection highlight (drawn behind text).
    /// Matches a system-blue tint at 30 % opacity: visually distinguishable and
    /// pixel-verifiable (blue channel > red channel after blending onto white).
    private static let selectionRed:   CGFloat = 0.20
    private static let selectionGreen: CGFloat = 0.47
    private static let selectionBlue:  CGFloat = 0.97
    private static let selectionAlpha: CGFloat = 0.30

    // MARK: - Public API

    /// Draws `layout` into `ctx`.
    ///
    /// - Parameters:
    ///   - layout:       The fully computed document layout.
    ///   - ctx:          A Core Graphics context whose coordinate system has its
    ///                   **origin at the bottom-left** (standard CG convention).
    ///   - canvasHeight: The full height of the drawing surface (view's
    ///                   `bounds.height`).  Used exclusively for the y-flip
    ///                   transform so that document-space coordinates map
    ///                   correctly onto the CG canvas regardless of scroll
    ///                   position.
    ///   - visible:      The rectangle (in document / view coordinates, y-down)
    ///                   that is currently on screen.  Used ONLY for culling:
    ///                   blocks that do not intersect this rectangle are skipped.
    ///   - selection:    An array of rects (document coordinates) to fill with
    ///                   the selection highlight color, drawn *behind* text.
    public static func draw(
        _ layout: DocumentLayout,
        in ctx: CGContext,
        canvasHeight: CGFloat,
        visible: CGRect,
        selection: [CGRect]
    ) {
        guard !layout.blocks.isEmpty || !selection.isEmpty else { return }

        // ------------------------------------------------------------------
        // Save graphics state so our transform does not leak to the caller.
        // ------------------------------------------------------------------
        ctx.saveGState()

        // ------------------------------------------------------------------
        // Coordinate flip: document space is y-down (origin top-left).
        // CG space is y-up (origin bottom-left).
        // We transform the context so that (0,0) in document space maps to the
        // top-left corner, with y increasing downward.
        //
        // We use canvasHeight (the full view bounds height) for the flip, NOT
        // visible.maxY.  In a scrolled view the dirty rect has a non-zero
        // origin and is shorter than the view, so using visible.maxY would
        // mis-place glyphs.  visible is used only for culling below.
        // ------------------------------------------------------------------
        ctx.translateBy(x: 0, y: canvasHeight)
        ctx.scaleBy(x: 1, y: -1)

        // ------------------------------------------------------------------
        // 1. Draw selection highlight rects (behind text)
        // ------------------------------------------------------------------
        if !selection.isEmpty {
            ctx.setFillColor(red: selectionRed, green: selectionGreen, blue: selectionBlue, alpha: selectionAlpha)
            for rect in selection {
                // Only draw if this selection rect intersects the visible area
                guard rect.intersects(visible) else { continue }
                ctx.fill(rect)
            }
        }

        // ------------------------------------------------------------------
        // 2. Draw blocks (text, list markers, quote bars, and nested layouts)
        // ------------------------------------------------------------------
        drawBlocks(layout.blocks, in: ctx, visible: visible)

        ctx.restoreGState()
    }

    // MARK: - Private drawing helpers

    /// Draws all blocks in `blocks`, handling text, lists, and quotes recursively.
    private static func drawBlocks(_ blocks: [BlockFrame], in ctx: CGContext, visible: CGRect) {
        for block in blocks {
            switch block {
            case .text(let blockRect, let lines):
                guard blockRect.intersects(visible) else { continue }
                drawTextLines(lines, in: ctx, visible: visible)

            case .list(let listRect, let itemLayouts, let markerFrames, let markerStrings):
                guard listRect.intersects(visible) else { continue }
                // Draw markers
                for (i, markerRect) in markerFrames.enumerated() {
                    guard i < markerStrings.count else { continue }
                    guard markerRect.intersects(visible) else { continue }
                    drawMarker(markerStrings[i], frame: markerRect, in: ctx)
                }
                // Recurse into each item's layout
                for itemLayout in itemLayouts {
                    drawBlocks(itemLayout.blocks, in: ctx, visible: visible)
                }

            case .quote(let quoteRect, let innerLayout, let barRect):
                guard quoteRect.intersects(visible) else { continue }
                // Draw the quote bar
                if barRect.intersects(visible) {
                    ctx.setFillColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
                    ctx.fill(barRect)
                }
                // Recurse into inner layout
                drawBlocks(innerLayout.blocks, in: ctx, visible: visible)

            case .rule(let rect):
                guard rect.intersects(visible) else { continue }
                // Draw thematic break as a thin horizontal line
                ctx.setFillColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
                ctx.fill(rect)

            case .table(let tableRect, _, let rowYs, let cellLines, let borders):
                guard tableRect.intersects(visible) else { continue }
                drawTable(rowYs: rowYs, cellLines: cellLines, borders: borders, in: ctx, visible: visible)

            case .code(let codeRect, let box, let lines, let langLabel):
                guard codeRect.intersects(visible) else { continue }
                drawCodeBlock(box: box, lines: lines, languageLabel: langLabel, in: ctx, visible: visible)

            case .image:
                break
            }
        }
    }

    /// Draws CoreText lines from a `.text` block.
    private static func drawTextLines(_ lines: [LineFrame], in ctx: CGContext, visible: CGRect) {
        for line in lines {
            let lineRect = CGRect(origin: line.origin, size: line.size)
            guard lineRect.intersects(visible) else { continue }

            // Baseline in document (y-down) space: origin.y + ascent.
            // The flip transform applied by the caller converts this to CG space correctly.
            let baseline = CGPoint(x: line.origin.x, y: line.origin.y + line.ascent)
            ctx.textMatrix = .identity
            ctx.textPosition = baseline
            CTLineDraw(line.ctLine, ctx)
        }
    }

    // MARK: - Table drawing

    /// Draws a GFM table: grid borders and all cell CTLines.
    private static func drawTable(
        rowYs: [CGFloat],
        cellLines: [[[LineFrame]]],
        borders: [CGRect],
        in ctx: CGContext,
        visible: CGRect
    ) {
        // Draw header row background FIRST so border strokes paint on top of it.
        if rowYs.count >= 2 {
            let headerRect = CGRect(
                x: borders.first?.minX ?? 0,
                y: rowYs[0],
                width: borders.first.map { _ in
                    // compute from last border
                    let allX = borders.map { $0.maxX }
                    return (allX.max() ?? 0) - (borders.map { $0.minX }.min() ?? 0)
                } ?? 0,
                height: rowYs[1] - rowYs[0]
            )
            if headerRect.intersects(visible) && headerRect.width > 0 {
                ctx.setFillColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1.0)
                ctx.fill(headerRect)
            }
        }

        // Draw border rects on top (thin dark lines, not overwritten by header fill)
        ctx.setFillColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
        for borderRect in borders {
            guard borderRect.intersects(visible) else { continue }
            ctx.fill(borderRect)
        }

        // Draw cell text lines
        for rowCellLines in cellLines {
            for cellLineFrames in rowCellLines {
                drawTextLines(cellLineFrames, in: ctx, visible: visible)
            }
        }
    }

    // MARK: - Code block drawing

    /// The fill color components for the code block background box.
    private static let codeBoxRed: CGFloat   = 0.95
    private static let codeBoxGreen: CGFloat = 0.95
    private static let codeBoxBlue: CGFloat  = 0.97

    /// Draws a code block: filled background box, optional language label, and monospace CTLines.
    private static func drawCodeBlock(
        box: CGRect,
        lines: [LineFrame],
        languageLabel: LineFrame?,
        in ctx: CGContext,
        visible: CGRect
    ) {
        // Fill the background box
        if box.intersects(visible) {
            ctx.setFillColor(red: codeBoxRed, green: codeBoxGreen, blue: codeBoxBlue, alpha: 1.0)
            ctx.fill(box)
        }

        // Draw language label (if any)
        if let label = languageLabel {
            let labelRect = CGRect(origin: label.origin, size: label.size)
            if labelRect.intersects(visible) {
                let baseline = CGPoint(x: label.origin.x, y: label.origin.y + label.ascent)
                ctx.textMatrix = .identity
                ctx.textPosition = baseline
                CTLineDraw(label.ctLine, ctx)
            }
        }

        // Draw code lines
        drawTextLines(lines, in: ctx, visible: visible)
    }

    /// Draws a single list marker string at the given frame position.
    private static func drawMarker(_ text: String, frame: CGRect, in ctx: CGContext) {
        // Build a minimal CTLine for the marker using the same default style as layout.
        let markerStyle = TextStyle(fontSize: 17, color: CGColor(gray: 0, alpha: 1))
        let markerFont = ctFont(for: markerStyle)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: markerFont,
            kCTForegroundColorAttributeName: markerStyle.color
        ]
        guard let attrStr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary) else { return }
        let typesetter = CTTypesetterCreateWithAttributedString(attrStr)
        let charCount = CFAttributedStringGetLength(attrStr)
        let ctLine = CTTypesetterCreateLine(typesetter, CFRangeMake(0, charCount))

        // Baseline: frame.origin.y + ascent (approximate — frame was built from the same ascent).
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading)

        let baseline = CGPoint(x: frame.origin.x, y: frame.origin.y + ascent)
        ctx.textMatrix = .identity
        ctx.textPosition = baseline
        CTLineDraw(ctLine, ctx)
    }
}
