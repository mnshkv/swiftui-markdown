// Only platform files import UIKit / AppKit / SwiftUI.
// Core files (Model/, Layout/, Selection/, Render/) must never import these.

import SwiftUI
import CoreGraphics

// MARK: - ImageProvider

/// An object that asynchronously resolves image sources to `CGImage`s.
///
/// Implement this protocol to supply images for inline image attachments.
/// All methods are called from an arbitrary `async` context.
public protocol ImageProvider: Sendable {
    /// Returns the image for `source` (a URL string or asset name), or `nil`
    /// if the image is unavailable or still loading.
    func image(for source: String) async -> CGImage?
}

// MARK: - EditMenuConfig

/// Configuration for the edit menu (Copy, Look Up, Share) shown when
/// a text selection is active.
///
/// Pass a custom value to `MarkdownTextView(editMenu:)` to hide individual
/// menu items; use `.standard` to show all three.
public struct EditMenuConfig: Sendable {
    /// Whether the "Copy" action is visible in the edit menu.
    public var showCopy: Bool
    /// Whether the "Look Up" action is visible in the edit menu.
    public var showLookUp: Bool
    /// Whether the "Share…" action is visible in the edit menu.
    public var showShare: Bool

    /// Creates an `EditMenuConfig` with explicit visibility for each item.
    public init(showCopy: Bool = true, showLookUp: Bool = true, showShare: Bool = true) {
        self.showCopy = showCopy
        self.showLookUp = showLookUp
        self.showShare = showShare
    }

    /// The standard edit menu: Copy, Look Up, and Share are all enabled.
    public static let standard = EditMenuConfig()
}

// MARK: - MarkdownTextView

/// A SwiftUI view that renders a `TextDocument` using CoreText + Core Graphics.
///
/// ## Supported features
/// - Paragraphs with inline styled text (bold, italic, monospace, links)
/// - Headings (h1–h6 via `ParagraphStyle.leadingIndent` / font size)
/// - Ordered and unordered lists (including nested lists)
/// - Block quotes with left-edge bar
/// - GFM tables (header + body rows, column alignment)
/// - Fenced code blocks (monospace, background tint, optional language label)
/// - Block-level and inline images (async loading via `ImageProvider`)
/// - Thematic breaks (horizontal rule)
/// - Link taps (inline link highlight on press + `onLink` callback)
/// - Document-wide text selection (drag / long-press, word selection on double-click/double-tap)
/// - Copy (plain text) via edit menu
/// - Word selection on double-click / double-tap
///
/// ## Documented limitations (v1)
/// - **Links inside block quotes / list items**: not yet tap/highlight-reachable
///   (hit-testing does not recurse into nested `DocumentLayout`s).
/// - **Selection loupe / magnifier**: deferred; handle knobs drawn at selection ends only.
/// - **RTL / bidirectional text**: deferred; LTR layout only.
/// - **Horizontal code scroll**: deferred; long code lines wrap inside the block.
/// - **Layout virtualization**: deferred; full layout is computed for the whole document;
///   only drawing is windowed (blocks outside the visible rect are skipped).
/// - **Rich / Markdown copy**: deferred; copy produces plain text only.
///
/// ### Architecture boundary
/// `MarkdownTextView` is a thin SwiftUI shim. All layout and drawing logic lives
/// in the pure `MarkdownTextEngine` core (`Layout/`, `Render/`), which has
/// zero UIKit/AppKit/SwiftUI imports.
@available(macOS 10.15, iOS 13, *)
@MainActor
public struct MarkdownTextView: View {

    // MARK: - Properties

    private let document: TextDocument
    private let isSelectable: Bool
    private let onLink: ((LinkPayload) -> Void)?
    private let images: (any ImageProvider)?
    private let editMenu: EditMenuConfig

    // MARK: - Initialiser

    /// Creates a `MarkdownTextView`.
    ///
    /// - Parameters:
    ///   - document:    The document to display.
    ///   - isSelectable: Whether the user can drag-select text (default `true`).
    ///   - onLink:      Called when the user taps a link run; receives the `LinkPayload`.
    ///   - images:      Provider for inline images (optional; images shown as placeholders
    ///                  until a provider is supplied).
    ///   - editMenu:    Edit-menu configuration (default `.standard`).
    public init(
        _ document: TextDocument,
        isSelectable: Bool = true,
        onLink: ((LinkPayload) -> Void)? = nil,
        images: (any ImageProvider)? = nil,
        editMenu: EditMenuConfig = .standard
    ) {
        self.document = document
        self.isSelectable = isSelectable
        self.onLink = onLink
        self.images = images
        self.editMenu = editMenu
    }

    // MARK: - Body

    public var body: some View {
        _TextEngineRepresentable(
            document: document,
            isSelectable: isSelectable,
            onLink: onLink,
            images: images,
            editMenu: editMenu
        )
        // intrinsicContentSize from TextEngineView drives this view's natural height.
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Platform representable

#if canImport(UIKit)
import UIKit

/// UIViewRepresentable that wraps `TextEngineView` for SwiftUI.
@available(iOS 13, *)
@MainActor
private struct _TextEngineRepresentable: UIViewRepresentable {

    let document: TextDocument
    let isSelectable: Bool
    let onLink: ((LinkPayload) -> Void)?
    let images: (any ImageProvider)?
    let editMenu: EditMenuConfig

    func makeUIView(context: Context) -> TextEngineView {
        let view = TextEngineView()
        view.document = document
        view.isSelectable = isSelectable
        view.editMenuConfig = editMenu
        view.imageProvider = images
        // Tap gesture for link detection
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: TextEngineView, context: Context) {
        uiView.document = document
        uiView.isSelectable = isSelectable
        uiView.editMenuConfig = editMenu
        uiView.imageProvider = images
        context.coordinator.onLink = onLink
        context.coordinator.view = uiView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLink: onLink)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject {
        var onLink: ((LinkPayload) -> Void)?
        weak var view: TextEngineView?

        init(onLink: ((LinkPayload) -> Void)?) {
            self.onLink = onLink
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view, let onLink else { return }
            let pt = gesture.location(in: view)
            let layout = view.docLayout
            // Use the module-level position(at:in:doc:) from HitTesting.swift
            let pos = hitTestPosition(at: pt, in: layout, doc: view.document)
            if let payload = linkPayload(at: pos, in: view.document) {
                onLink(payload)
            }
        }
    }
}

#elseif canImport(AppKit)
import AppKit

/// NSViewRepresentable that wraps `TextEngineView` for SwiftUI.
@available(macOS 10.15, *)
@MainActor
private struct _TextEngineRepresentable: NSViewRepresentable {

    let document: TextDocument
    let isSelectable: Bool
    let onLink: ((LinkPayload) -> Void)?
    let images: (any ImageProvider)?
    let editMenu: EditMenuConfig

    func makeNSView(context: Context) -> TextEngineView {
        let view = TextEngineView()
        view.document = document
        view.isSelectable = isSelectable
        view.editMenuConfig = editMenu
        view.imageProvider = images
        // Click gesture for link detection
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        view.addGestureRecognizer(click)
        return view
    }

    func updateNSView(_ nsView: TextEngineView, context: Context) {
        nsView.document = document
        nsView.isSelectable = isSelectable
        nsView.editMenuConfig = editMenu
        nsView.imageProvider = images
        context.coordinator.onLink = onLink
        context.coordinator.view = nsView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLink: onLink)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject {
        var onLink: ((LinkPayload) -> Void)?
        weak var view: TextEngineView?

        init(onLink: ((LinkPayload) -> Void)?) {
            self.onLink = onLink
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view, let onLink else { return }
            // NSView coordinates: y increases upward from bottom (not flipped).
            // Convert from AppKit y-up to document y-down.
            let ptInView = gesture.location(in: view)
            let docPt = CGPoint(x: ptInView.x, y: view.bounds.height - ptInView.y)
            let layout = view.docLayout
            // Use the module-level position(at:in:doc:) from HitTesting.swift
            let pos = hitTestPosition(at: docPt, in: layout, doc: view.document)
            if let payload = linkPayload(at: pos, in: view.document) {
                onLink(payload)
            }
        }
    }
}

#endif

// MARK: - Forwarding wrapper for position(at:in:doc:)
//
// The global function `position(at:in:doc:)` from HitTesting.swift would
// shadow NSGestureRecognizer.location(in:) and UIGestureRecognizer methods
// in coordinator scope. We wrap it with an unambiguous name.

private func hitTestPosition(at point: CGPoint, in layout: DocumentLayout, doc: TextDocument) -> TextPosition {
    position(at: point, in: layout, doc: doc)
}

// MARK: - Link hit-test helper

/// Returns the `LinkPayload` at the given text `position` in `doc`, if any.
///
/// Walks the block at the position's block index and inspects the inline run
/// under the character offset to find a `.link` run.
private func linkPayload(at pos: TextPosition, in doc: TextDocument) -> LinkPayload? {
    // Use the flattened text bases to find which block and offset within it.
    let bases = utf16Bases(for: doc)
    let flat = flattenedText(doc)
    let total = flat.utf16.count
    let idx = max(0, min(pos.index, total))

    // Find the block that contains this position
    var blockIndex: Int? = nil
    for (i, base) in bases.enumerated() {
        let nextBase = (i + 1 < bases.count) ? bases[i + 1] : total + 1
        if idx >= base && idx < nextBase {
            blockIndex = i
            break
        }
    }
    guard let bi = blockIndex else { return nil }
    let block = doc.blocks[bi]
    guard case .paragraph(let para) = block else { return nil }

    let localOffset = idx - bases[bi]
    return linkPayloadInRuns(at: localOffset, in: para.runs)
}

/// Recursively searches `runs` for a `.link` run that covers `offset`
/// (a UTF-16 offset within the paragraph's flattened text).
private func linkPayloadInRuns(at offset: Int, in runs: [InlineRun]) -> LinkPayload? {
    var cursor = 0
    for run in runs {
        switch run {
        case .text(let s, _):
            let len = s.utf16.count
            if offset >= cursor && offset < cursor + len { return nil }
            cursor += len

        case .link(let innerRuns, let payload):
            let innerText = innerRuns.map { inlineRunText($0) }.joined()
            let len = innerText.utf16.count
            if offset >= cursor && offset < cursor + len {
                return payload
            }
            cursor += len

        case .inlineImage:
            break

        case .lineBreak(let hard):
            let ch = hard ? "\n" : "\u{2028}"
            cursor += ch.utf16.count
        }
    }
    return nil
}

/// Returns the plain-text contribution of a single inline run.
private func inlineRunText(_ run: InlineRun) -> String {
    switch run {
    case .text(let s, _): return s
    case .link(let inner, _): return inner.map { inlineRunText($0) }.joined()
    case .inlineImage: return ""
    case .lineBreak(let hard): return hard ? "\n" : "\u{2028}"
    }
}
