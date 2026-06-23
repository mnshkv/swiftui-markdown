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
    ///   - layout:    The fully computed document layout.
    ///   - ctx:       A Core Graphics context whose coordinate system has its
    ///                **origin at the bottom-left** (standard CG convention).
    ///                The context's height must be passed implicitly via the
    ///                `visible` rect; the renderer uses `visible.maxY` as the
    ///                canvas height for the y-flip.
    ///   - visible:   The rectangle (in document / view coordinates, y-down) that
    ///                is currently on screen.  Blocks that do not intersect this
    ///                rectangle are skipped.
    ///   - selection: An array of rects (document coordinates) to fill with the
    ///                selection highlight color, drawn *behind* text.
    public static func draw(
        _ layout: DocumentLayout,
        in ctx: CGContext,
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
        // The canvas height we use is visible.maxY; this is the total height
        // of the drawing surface visible in this draw call.  For a windowed
        // draw pass, visible.maxY == viewBounds.maxY.
        // ------------------------------------------------------------------
        let canvasHeight = visible.maxY
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
        // 2. Draw text blocks
        // ------------------------------------------------------------------
        for block in layout.blocks {
            guard case .text(let blockRect, let lines) = block else { continue }
            // Skip blocks entirely outside the visible rect
            guard blockRect.intersects(visible) else { continue }

            for line in lines {
                // Skip individual lines outside the visible rect
                let lineRect = CGRect(origin: line.origin, size: line.size)
                guard lineRect.intersects(visible) else { continue }

                // The baseline in document (y-down) space is:
                //   line.origin.y + line.ascent
                // After the flip, the CG y coordinate is:
                //   line.origin.y + line.ascent  (same value — the transform handles it)
                let baseline = CGPoint(x: line.origin.x, y: line.origin.y + line.ascent)
                ctx.textMatrix = .identity
                ctx.textPosition = baseline
                CTLineDraw(line.ctLine, ctx)
            }
        }

        ctx.restoreGState()
    }
}
