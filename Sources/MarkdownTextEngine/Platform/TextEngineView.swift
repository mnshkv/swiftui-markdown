// Only platform files import UIKit / AppKit. Core files (Model/, Layout/, Selection/, Render/)
// must never import these frameworks.

#if canImport(UIKit)
import UIKit
import CoreGraphics

/// A UIView that lays out and renders a `TextDocument` using `DocumentRenderer`.
///
/// - Recomputes `DocumentLayout` whenever the view's width changes.
/// - Exposes `intrinsicContentSize` equal to the layout's `contentSize`.
/// - Draws windowed: only the portion covered by the dirty rect is rendered.
/// - Supports basic drag selection via `TextRange`; updated externally or by
///   `TextEngineView`'s own gesture recogniser (added in Task 3.4).
@MainActor
public final class TextEngineView: UIView {

    // MARK: - Public state

    /// The document to display.
    public var document: TextDocument = TextDocument(blocks: []) {
        didSet { setNeedsLayout() }
    }

    /// The currently highlighted selection rects (document coordinates).
    public var currentSelectionRects: [CGRect] = [] {
        didSet { setNeedsDisplay() }
    }

    // MARK: - Private state

    private var docLayout: DocumentLayout = DocumentLayout(blocks: [], contentSize: .zero)
    private var lastLayoutWidth: CGFloat = 0

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        guard w > 0, w != lastLayoutWidth else { return }
        lastLayoutWidth = w
        docLayout = LayoutEngine.layout(document, width: w)
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    public override var intrinsicContentSize: CGSize {
        docLayout.contentSize
    }

    // MARK: - Drawing

    public override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        DocumentRenderer.draw(docLayout, in: ctx, visible: rect, selection: currentSelectionRects)
    }
}

#elseif canImport(AppKit)
import AppKit
import CoreGraphics

/// An NSView that lays out and renders a `TextDocument` using `DocumentRenderer`.
///
/// - Recomputes `DocumentLayout` whenever the view's width changes.
/// - Exposes `intrinsicContentSize` equal to the layout's `contentSize`.
/// - Draws windowed: only the portion covered by the dirty rect is rendered.
/// - Supports basic drag selection via `TextRange`; updated externally or by
///   `TextEngineView`'s own gesture recogniser (added in Task 3.4).
@MainActor
public final class TextEngineView: NSView {

    // MARK: - Public state

    /// The document to display.
    public var document: TextDocument = TextDocument(blocks: []) {
        didSet { needsLayout = true }
    }

    /// The currently highlighted selection rects (document coordinates).
    public var currentSelectionRects: [CGRect] = [] {
        didSet { needsDisplay = true }
    }

    // MARK: - Private state

    private var docLayout: DocumentLayout = DocumentLayout(blocks: [], contentSize: .zero)
    private var lastLayoutWidth: CGFloat = 0

    // MARK: - Initialisation

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // NSView does not automatically flip its coordinate system; we use the
        // standard AppKit convention (y-up at bottom-left) and let DocumentRenderer
        // handle the flip internally.
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Layout

    public override func layout() {
        super.layout()
        let w = bounds.width
        guard w > 0, w != lastLayoutWidth else { return }
        lastLayoutWidth = w
        docLayout = LayoutEngine.layout(document, width: w)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    public override var intrinsicContentSize: NSSize {
        docLayout.contentSize
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // On AppKit, NSView draws with y-up (bottom-left origin) by default.
        // DocumentRenderer's draw() applies the y-flip internally using visible.maxY
        // as the canvas height; we pass the view bounds height via a full-bounds
        // visible rect and let the renderer clip to dirtyRect at the block level.
        let visibleRect = CGRect(origin: dirtyRect.origin,
                                 size: CGSize(width: dirtyRect.width, height: dirtyRect.height))
        DocumentRenderer.draw(docLayout, in: ctx, visible: visibleRect, selection: currentSelectionRects)
    }
}
#endif
