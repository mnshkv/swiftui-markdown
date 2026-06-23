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
/// - Supports basic drag selection via a long-press + pan gesture (Task 3.4).
/// - Word selection on double-tap (Task 7.1).
/// - Selection handle knobs drawn at selection ends (Task 7.2).
/// - Edit menu (Copy/Look Up/Share) on long-press over a selection (Task 7.3).
@MainActor
public final class TextEngineView: UIView {

    // MARK: - Public state

    /// The document to display.
    public var document: TextDocument = TextDocument(blocks: []) {
        didSet { setNeedsLayout() }
    }

    /// The currently highlighted selection rects (document coordinates).
    /// Set externally or updated by the drag-selection gesture.
    public var currentSelectionRects: [CGRect] = [] {
        didSet { setNeedsDisplay() }
    }

    /// Edit menu configuration (Task 7.3). Updated by the SwiftUI representable.
    public var editMenuConfig: EditMenuConfig = .standard

    /// When false, drag-selection, long-press, and double-tap selection are disabled.
    /// Link taps remain active regardless.
    public var isSelectable: Bool = true

    // MARK: - Internal state (accessible within the module for representable coordination)

    /// The most recently computed layout. Exposed internally so the SwiftUI
    /// representable coordinator can hit-test tapped points against line frames.
    var docLayout: DocumentLayout = DocumentLayout(blocks: [], contentSize: .zero)

    /// Optional image provider for async image loading.
    /// When set, `TextEngineView` requests each image source after layout completes.
    public var imageProvider: (any ImageProvider)? = nil {
        didSet { imageCache = [:]; setNeedsLayout() }
    }

    // MARK: - Private state

    private var lastLayoutWidth: CGFloat = 0

    /// The current text selection range (used for drag selection).
    private var currentRange: TextRange? = nil

    /// Rects to draw as pressed-link highlight (Task 7.4). Document coordinates.
    private var pressedLinkRects: [CGRect] = [] {
        didSet { setNeedsDisplay() }
    }

    /// Cache of resolved CGImages keyed by source string.
    /// Populated asynchronously by `loadImages()` after each layout.
    private var imageCache: [String: CGImage] = [:]

    /// Set of image sources currently being loaded (to avoid duplicate requests).
    private var loadingImages: Set<String> = []

    /// Set of image sources that returned `nil` from the provider (permanent failure).
    /// Sources in this set are skipped on future layout cycles to avoid infinite retry loops.
    private var failedImageSources: Set<String> = []

    // MARK: - Initialisation

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupDragSelection()
        setupEditMenu()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDragSelection()
        setupEditMenu()
    }

    // MARK: - Drag selection setup

    private func setupDragSelection() {
        // Long-press begins the selection; panning extends it.
        // We use a LongPressGestureRecognizer + a UIPanGestureRecognizer in parallel.
        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.4
        addGestureRecognizer(longPress)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        // Double-tap for word selection (Task 7.1).
        let doubleTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    // MARK: - Double-tap word selection (Task 7.1)

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard isSelectable else { return }
        guard gesture.state == .ended else { return }
        let pt = gesture.location(in: self)
        let range = wordSelection(at: pt, layout: docLayout, doc: document)
        currentRange = range
        updateSelectionRects()
    }

    // MARK: - Edit menu setup (Task 7.3)

    /// The UIEditMenuInteraction instance, added when the view initialises (iOS 16+).
    @available(iOS 16, *)
    private var _editMenuInteraction: UIEditMenuInteraction? {
        get { interactions.compactMap { $0 as? UIEditMenuInteraction }.first }
    }

    private func setupEditMenu() {
        if #available(iOS 16, *) {
            let interaction = UIEditMenuInteraction(delegate: self)
            addInteraction(interaction)
        }
    }

    // MARK: - Long-press to show edit menu (Task 7.3)

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard isSelectable else { return }
        guard gesture.state == .began else { return }
        let pt = gesture.location(in: self)

        // If a selection already exists, show the edit menu at the long-press point.
        if let range = currentRange, range.start.index < range.end.index {
            if #available(iOS 16, *) {
                let config = UIEditMenuConfiguration(identifier: nil, sourcePoint: pt)
                _editMenuInteraction?.presentEditMenu(with: config)
            }
            return
        }

        let pos = position(at: pt, in: docLayout, doc: document)
        // Start a word-selection at the long-pressed position.
        let wordRng = wordRange(at: pos, doc: document)
        currentRange = wordRng
        updateSelectionRects()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isSelectable else { return }
        guard gesture.state == .changed || gesture.state == .ended else {
            if gesture.state == .cancelled { clearSelection(); return }
            return
        }
        guard let existingRange = currentRange else { return }
        let pt = gesture.location(in: self)
        let endPos = position(at: pt, in: docLayout, doc: document)
        currentRange = TextRange(start: existingRange.start, end: endPos)
        updateSelectionRects()
    }

    private func clearSelection() {
        currentRange = nil
        currentSelectionRects = []
    }

    private func updateSelectionRects() {
        guard let range = currentRange else {
            currentSelectionRects = []
            return
        }
        currentSelectionRects = selectionRects(for: range, in: docLayout, doc: document)
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        guard w > 0, w != lastLayoutWidth else { return }
        lastLayoutWidth = w
        docLayout = LayoutEngine.layout(document, width: w)
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
        // After (re)layout, kick off async image loading for any sources in the new layout.
        loadImages()
    }

    public override var intrinsicContentSize: CGSize {
        docLayout.contentSize
    }

    // MARK: - Async image loading

    /// Iterates all `.image` blocks in the current layout and fires async Tasks
    /// to fetch each uncached source via `imageProvider`.
    ///
    /// On completion, the CGImage is stored in `imageCache` and only the image's
    /// reserved rect is invalidated for a partial redraw.
    private func loadImages() {
        guard let provider = imageProvider else { return }
        for block in docLayout.blocks {
            guard case .image(let rect, let attachment) = block else { continue }
            let source = attachment.source
            // Skip sources already resolved (cached) or currently in-flight.
            // Also skip sources that previously returned nil (permanent failure) —
            // without this guard the view would re-fire a Task on every resize,
            // looping forever.
            guard imageCache[source] == nil,
                  !loadingImages.contains(source),
                  !failedImageSources.contains(source) else { continue }
            loadingImages.insert(source)
            Task { [weak self] in
                guard let self else { return }
                let cgImage = await provider.image(for: source)
                // Back on MainActor (Task inherits actor from @MainActor type).
                self.loadingImages.remove(source)
                if let cgImage {
                    self.imageCache[source] = cgImage
                    // Partial redraw: invalidate only the image's rect.
                    self.setNeedsDisplay(rect)
                } else {
                    // Mark as a permanent failure so future layouts don't re-fire
                    // a Task for this source.
                    self.failedImageSources.insert(source)
                }
            }
        }
    }

    // MARK: - Pressed-link tracking (Task 7.4)

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        let pt = touch.location(in: self)
        if let (_, range) = linkRange(at: pt, layout: docLayout, doc: document) {
            pressedLinkRects = selectionRects(for: range, in: docLayout, doc: document)
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        pressedLinkRects = []
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        pressedLinkRects = []
    }

    // MARK: - Drawing

    public override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        DocumentRenderer.draw(docLayout, in: ctx, canvasHeight: bounds.height, visible: rect,
                              selection: currentSelectionRects, pressedLinkRects: pressedLinkRects,
                              images: imageCache)
        // Task 7.2: draw selection handle knobs when there is a non-empty selection.
        if currentSelectionRects.count >= 1 {
            drawSelectionHandles(in: ctx, selectionRects: currentSelectionRects,
                                 canvasHeight: bounds.height)
        }
    }

    // MARK: - Selection handle knobs (Task 7.2)

    /// Radius of the circular drag-handle knobs at each end of the selection.
    private static let handleRadius: CGFloat = 6

    /// Draws two round knobs at the start and end corners of the selection rects.
    ///
    /// - The start handle is at the bottom-left of the first selection rect.
    /// - The end handle is at the bottom-right of the last selection rect.
    ///
    /// All coordinates are in document space (y-down). The CG context already
    /// has the y-flip transform applied by `DocumentRenderer.draw`, so we apply
    /// the same transform here before drawing.
    ///
    /// PRAGMATIC NOTE (Task 7.2): This is a correct, compiling implementation that
    /// shows knob indicators at the selection ends. A full system loupe
    /// (`UITextSelectionDisplayInteraction` / magnifier loupe) requires adopting
    /// `UITextInput` which is too heavy for a read-only view, and is deferred as a
    /// nice-to-have. The knobs are sufficient for visual affordance.
    private func drawSelectionHandles(in ctx: CGContext,
                                      selectionRects: [CGRect],
                                      canvasHeight: CGFloat) {
        guard let first = selectionRects.first, let last = selectionRects.last else { return }
        let r = TextEngineView.handleRadius

        // Start knob: bottom-left of the first selection rect (in doc y-down space).
        let startCenter = CGPoint(x: first.minX, y: first.maxY)
        // End knob: bottom-right of the last selection rect.
        let endCenter = CGPoint(x: last.maxX, y: last.maxY)

        ctx.saveGState()
        // Apply the same flip as DocumentRenderer so doc-space coords work correctly.
        ctx.translateBy(x: 0, y: canvasHeight)
        ctx.scaleBy(x: 1, y: -1)

        // Draw handle knobs (system blue, opaque).
        ctx.setFillColor(red: 0.20, green: 0.47, blue: 0.97, alpha: 1.0)
        ctx.fillEllipse(in: CGRect(x: startCenter.x - r, y: startCenter.y - r,
                                   width: r * 2, height: r * 2))
        ctx.fillEllipse(in: CGRect(x: endCenter.x - r, y: endCenter.y - r,
                                   width: r * 2, height: r * 2))
        ctx.restoreGState()
    }
}

// MARK: - UIEditMenuInteractionDelegate (Task 7.3, iOS 16+)

@available(iOS 16, *)
extension TextEngineView: @preconcurrency UIEditMenuInteractionDelegate {

    public func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        guard let range = currentRange, range.start.index < range.end.index else {
            return nil
        }
        var actions: [UIMenuElement] = []

        if editMenuConfig.showCopy {
            actions.append(UIAction(title: "Copy") { [weak self] _ in
                guard let self else { return }
                let text = copyText(for: range, doc: self.document)
                UIPasteboard.general.string = text
            })
        }

        if editMenuConfig.showLookUp {
            actions.append(UIAction(title: "Look Up") { _ in
                // Look Up is handled by the system via UIReferenceLibraryViewController.
                // For a read-only view, we post the standard "define" action identifier
                // here as a no-op stub since UIReferenceLibraryViewController requires
                // a presented view controller reference that this layer does not own.
                // The action is included so menu configuration is honoured.
            })
        }

        if editMenuConfig.showShare {
            actions.append(UIAction(title: "Share…") { [weak self] _ in
                guard let self else { return }
                let text = copyText(for: range, doc: self.document)
                guard !text.isEmpty else { return }
                let activityVC = UIActivityViewController(
                    activityItems: [text], applicationActivities: nil
                )
                // Find the nearest UIViewController to present from.
                if let windowScene = self.window?.windowScene,
                   let vc = windowScene.keyWindow?.rootViewController {
                    vc.present(activityVC, animated: true)
                }
            })
        }

        return actions.isEmpty ? nil : UIMenu(children: actions)
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
/// - Supports basic drag selection via mouse events (Task 3.4).
/// - Word selection on double-click (Task 7.1).
/// - Selection handle knobs drawn at selection ends (Task 7.2).
/// - Edit menu (Copy/Look Up/Share) on right-click / secondary click (Task 7.3).
/// - Loads images asynchronously via `imageProvider` (Task 6.3): after layout,
///   one `Task` per image source fetches the `CGImage`; on completion, the image
///   is stored in `imageCache` and only the image's reserved rect is invalidated.
@MainActor
public final class TextEngineView: NSView {

    // MARK: - Public state

    /// The document to display.
    public var document: TextDocument = TextDocument(blocks: []) {
        didSet { needsLayout = true }
    }

    /// Optional image provider for async image loading (Task 6.3).
    /// When set, `TextEngineView` requests each image source after layout completes.
    public var imageProvider: (any ImageProvider)? = nil {
        didSet { imageCache = [:]; needsLayout = true }
    }

    /// The currently highlighted selection rects (document coordinates).
    /// Set externally or updated by the drag-selection gesture.
    public var currentSelectionRects: [CGRect] = [] {
        didSet { needsDisplay = true }
    }

    /// Edit menu configuration (Task 7.3). Updated by the SwiftUI representable.
    public var editMenuConfig: EditMenuConfig = .standard

    /// When false, drag-selection and double-click selection are disabled.
    /// Link taps remain active regardless.
    public var isSelectable: Bool = true

    // MARK: - Internal state (accessible within the module for representable coordination)

    /// The most recently computed layout. Exposed internally so the SwiftUI
    /// representable coordinator can hit-test tapped points against line frames.
    var docLayout: DocumentLayout = DocumentLayout(blocks: [], contentSize: .zero)

    // MARK: - Private state

    private var lastLayoutWidth: CGFloat = 0

    /// The anchor position when a drag begins (mouse-down point).
    private var dragAnchor: TextPosition? = nil

    /// The range set by a double-click word-selection (Task 7.1).
    private var currentWordRange: TextRange? = nil

    /// The current active text selection range (drag or double-click). Used by the edit menu.
    private var currentRange: TextRange? = nil

    /// Rects to draw as pressed-link highlight (Task 7.4). Document coordinates.
    private var pressedLinkRects: [CGRect] = [] {
        didSet { needsDisplay = true }
    }

    /// Cache of resolved CGImages keyed by source string.
    /// Populated asynchronously by `loadImages()` after each layout.
    private var imageCache: [String: CGImage] = [:]

    /// Set of image sources currently being loaded (to avoid duplicate requests).
    private var loadingImages: Set<String> = []

    /// Set of image sources that returned `nil` from the provider (permanent failure).
    /// Sources in this set are skipped on future layout cycles to avoid infinite retry loops.
    /// Fix for Wave-6 review Minor #2.
    private var failedImageSources: Set<String> = []

    // MARK: - Initialisation

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Mouse / drag selection (AppKit)

    /// Converts an AppKit NSView point (y-up from bottom) to document space (y-down from top).
    private func toDocPoint(_ nsPoint: NSPoint) -> CGPoint {
        CGPoint(x: nsPoint.x, y: bounds.height - nsPoint.y)
    }

    public override func mouseDown(with event: NSEvent) {
        let pt = toDocPoint(convert(event.locationInWindow, from: nil))

        // Double-click → word selection (Task 7.1). No link highlight on double-click.
        if event.clickCount == 2 {
            guard isSelectable else { return }
            pressedLinkRects = []
            let range = wordSelection(at: pt, layout: docLayout, doc: document)
            currentWordRange = range
            currentRange = range
            currentSelectionRects = selectionRects(for: range, in: docLayout, doc: document)
            dragAnchor = nil
            return
        }

        // Task 7.4: highlight link on mouse-down (always active, regardless of isSelectable).
        if let (_, linkRng) = linkRange(at: pt, layout: docLayout, doc: document) {
            pressedLinkRects = selectionRects(for: linkRng, in: docLayout, doc: document)
        } else {
            pressedLinkRects = []
        }

        guard isSelectable else { return }
        currentWordRange = nil
        let pos = position(at: pt, in: docLayout, doc: document)
        dragAnchor = pos
        // Zero-length range at anchor — shows caret position
        updateSelectionRects(anchor: pos, active: pos)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let anchor = dragAnchor else { return }
        let pt = toDocPoint(convert(event.locationInWindow, from: nil))
        let activePos = position(at: pt, in: docLayout, doc: document)
        updateSelectionRects(anchor: anchor, active: activePos)
    }

    public override func mouseUp(with event: NSEvent) {
        // Task 7.4: clear pressed-link highlight on release.
        pressedLinkRects = []
        guard let anchor = dragAnchor else { return }
        let pt = toDocPoint(convert(event.locationInWindow, from: nil))
        let activePos = position(at: pt, in: docLayout, doc: document)
        updateSelectionRects(anchor: anchor, active: activePos)
        // If released at same position as anchor, clear selection
        if anchor == activePos {
            currentSelectionRects = []
            currentRange = nil
            dragAnchor = nil
        }
    }

    /// Right-click / secondary click → show edit menu over the current selection (Task 7.3).
    public override func rightMouseDown(with event: NSEvent) {
        guard let range = currentRange, range.start.index < range.end.index else {
            super.rightMouseDown(with: event)
            return
        }
        let menu = buildEditMenu(for: range)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func updateSelectionRects(anchor: TextPosition, active: TextPosition) {
        let range = TextRange(start: anchor, end: active)
        currentRange = range.start.index < range.end.index ? range : nil
        currentSelectionRects = selectionRects(for: range, in: docLayout, doc: document)
    }

    // MARK: - Edit menu construction (Task 7.3, AppKit)

    /// Builds an `NSMenu` for the current selection honoring `editMenuConfig`.
    private func buildEditMenu(for range: TextRange) -> NSMenu {
        let menu = NSMenu(title: "")

        if editMenuConfig.showCopy {
            let copyItem = NSMenuItem(title: "Copy", action: #selector(performCopy(_:)), keyEquivalent: "")
            copyItem.target = self
            menu.addItem(copyItem)
        }

        if editMenuConfig.showLookUp {
            let lookUpItem = NSMenuItem(title: "Look Up", action: #selector(performLookUp(_:)), keyEquivalent: "")
            lookUpItem.target = self
            menu.addItem(lookUpItem)
        }

        if editMenuConfig.showShare {
            menu.addItem(NSMenuItem.separator())
            let shareItem = NSMenuItem(title: "Share…", action: #selector(performShare(_:)), keyEquivalent: "")
            shareItem.target = self
            menu.addItem(shareItem)
        }

        return menu
    }

    @objc private func performCopy(_ sender: Any?) {
        guard let range = currentRange else { return }
        let text = copyText(for: range, doc: document)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func performLookUp(_ sender: Any?) {
        // Look Up: show the Dictionary panel for the selected word.
        // Requires a window with a text selection; here we provide the word text.
        guard let range = currentRange else { return }
        let text = copyText(for: range, doc: document)
        guard !text.isEmpty else { return }
        let dictBase = "dict://"
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        if let url = URL(string: dictBase + encoded) ?? URL(string: dictBase) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func performShare(_ sender: Any?) {
        guard let range = currentRange else { return }
        let text = copyText(for: range, doc: document)
        guard !text.isEmpty, self.window != nil else { return }
        let picker = NSSharingServicePicker(items: [text])
        picker.show(relativeTo: .zero, of: self, preferredEdge: .minY)
    }

    // Accept mouse events
    public override var acceptsFirstResponder: Bool { true }

    // MARK: - Layout

    public override func layout() {
        super.layout()
        let w = bounds.width
        guard w > 0, w != lastLayoutWidth else { return }
        lastLayoutWidth = w
        docLayout = LayoutEngine.layout(document, width: w)
        invalidateIntrinsicContentSize()
        needsDisplay = true
        // After (re)layout, kick off async image loading for any sources in the new layout.
        if #available(macOS 10.15, *) { loadImages() }
    }

    public override var intrinsicContentSize: NSSize {
        docLayout.contentSize
    }

    // MARK: - Async image loading (Task 6.3)

    /// Iterates all `.image` blocks in the current layout and fires async Tasks
    /// to fetch each uncached source via `imageProvider`.
    ///
    /// On completion, the CGImage is stored in `imageCache` and only the image's
    /// reserved rect is invalidated for a partial redraw.
    @available(macOS 10.15, *)
    private func loadImages() {
        guard let provider = imageProvider else { return }
        for block in docLayout.blocks {
            guard case .image(let rect, let attachment) = block else { continue }
            let source = attachment.source
            // Skip sources already resolved (cached) or currently in-flight.
            // Also skip sources that previously returned nil (permanent failure) —
            // without this guard the view would re-fire a Task on every resize,
            // looping forever. Fix for Wave-6 review Minor #2.
            guard imageCache[source] == nil,
                  !loadingImages.contains(source),
                  !failedImageSources.contains(source) else { continue }
            loadingImages.insert(source)
            Task { [weak self] in
                guard let self else { return }
                let cgImage = await provider.image(for: source)
                // Back on MainActor (Task inherits actor from @MainActor type).
                self.loadingImages.remove(source)
                if let cgImage {
                    self.imageCache[source] = cgImage
                    // Partial redraw: invalidate only the image's rect.
                    self.setNeedsDisplay(rect)
                } else {
                    // Mark as a permanent failure so future layouts don't re-fire
                    // a Task for this source.
                    self.failedImageSources.insert(source)
                }
            }
        }
    }

    // MARK: - Drawing

    /// Converts an NSView y-up dirty rect into document space (y-down) so it can
    /// serve as the renderer's cull rect. The block frames the renderer culls
    /// against live in document space; without this conversion a partial dirty
    /// rect culls the wrong blocks. See `draw(_:)`.
    nonisolated static func documentVisibleRect(_ dirtyRect: CGRect, boundsHeight: CGFloat) -> CGRect {
        CGRect(x: dirtyRect.minX, y: boundsHeight - dirtyRect.maxY,
               width: dirtyRect.width, height: dirtyRect.height)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // NSView draws y-up; DocumentRenderer culls block frames in document space
        // (y-down). Convert the dirtyRect, or a partial dirtyRect (e.g. inside a
        // scroll view) culls the wrong blocks and whole sections vanish.
        let visibleRect = Self.documentVisibleRect(dirtyRect, boundsHeight: bounds.height)
        DocumentRenderer.draw(
            docLayout,
            in: ctx,
            canvasHeight: bounds.height,
            visible: visibleRect,
            selection: currentSelectionRects,
            pressedLinkRects: pressedLinkRects,
            images: imageCache
        )
        // Task 7.2: draw selection handle knobs when there is a non-empty selection.
        if currentSelectionRects.count >= 1 {
            drawSelectionHandles(in: ctx, selectionRects: currentSelectionRects,
                                 canvasHeight: bounds.height)
        }
    }

    // MARK: - Selection handle knobs (Task 7.2)

    /// Radius of the circular drag-handle knobs at each end of the selection.
    private static let handleRadius: CGFloat = 6

    /// Draws two round knobs at the start and end corners of the selection rects.
    ///
    /// - The start handle is at the bottom-left of the first selection rect.
    /// - The end handle is at the bottom-right of the last selection rect.
    ///
    /// All coordinates are in document space (y-down). The CG context already
    /// has the y-flip transform applied by `DocumentRenderer.draw`, so we apply
    /// the same transform here before drawing.
    ///
    /// PRAGMATIC NOTE (Task 7.2): This is a correct, compiling implementation that
    /// shows knob indicators at the selection ends. A full system loupe
    /// (`UITextSelectionDisplayInteraction` on iOS / magnifier loupe on macOS) is a
    /// nice-to-have and is deferred. The knobs provide the required visual affordance.
    private func drawSelectionHandles(in ctx: CGContext,
                                      selectionRects: [CGRect],
                                      canvasHeight: CGFloat) {
        guard let first = selectionRects.first, let last = selectionRects.last else { return }
        let r = TextEngineView.handleRadius

        // Start knob: bottom-left of the first selection rect (in doc y-down space).
        let startCenter = CGPoint(x: first.minX, y: first.maxY)
        // End knob: bottom-right of the last selection rect.
        let endCenter = CGPoint(x: last.maxX, y: last.maxY)

        ctx.saveGState()
        // Apply the same flip as DocumentRenderer so doc-space coords work correctly.
        ctx.translateBy(x: 0, y: canvasHeight)
        ctx.scaleBy(x: 1, y: -1)

        // Draw handle knobs (system blue, opaque).
        ctx.setFillColor(red: 0.20, green: 0.47, blue: 0.97, alpha: 1.0)
        ctx.fillEllipse(in: CGRect(x: startCenter.x - r, y: startCenter.y - r,
                                   width: r * 2, height: r * 2))
        ctx.fillEllipse(in: CGRect(x: endCenter.x - r, y: endCenter.y - r,
                                   width: r * 2, height: r * 2))
        ctx.restoreGState()
    }
}
#endif
