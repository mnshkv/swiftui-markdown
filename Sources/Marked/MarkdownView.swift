#if canImport(SwiftUI)
import SwiftUI

// MARK: - MarkdownView

/// A SwiftUI view that renders a Markdown string using the full Marked pipeline.
///
/// `MarkdownView` is the one-line public entry point: it parses the string,
/// applies the style and color scheme, and delegates all layout/drawing to
/// `MarkdownTextView`.
///
/// ```swift
/// MarkdownView("# Hello\nSome **bold** text and a [link](https://swift.org).")
/// ```
///
/// Link taps are dispatched through `onLink`. If `onLink` is not provided,
/// `https:` / `http:` links are opened with the environment's `openURL` action.
@available(iOS 26, macOS 14, *)
@MainActor
public struct MarkdownView: View {

    // MARK: - Stored inputs

    private let markdown: String
    private let style: MarkdownStyle
    private let images: (any ImageProvider)?
    private let isSelectable: Bool
    private let onLink: ((URL) -> Void)?

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    // MARK: - Initialiser

    /// Creates a `MarkdownView`.
    ///
    /// - Parameters:
    ///   - markdown:     The Markdown string to render.
    ///   - style:        The visual style to apply (default `.default`).
    ///   - images:       Optional image provider for inline images.
    ///   - isSelectable: Whether the user can select text (default `true`).
    ///   - onLink:       Called when the user taps a link whose token resolves to a URL.
    ///                   If `nil`, links are opened with the environment `openURL` action.
    public init(
        _ markdown: String,
        style: MarkdownStyle = .default,
        images: (any ImageProvider)? = nil,
        isSelectable: Bool = true,
        onLink: ((URL) -> Void)? = nil
    ) {
        self.markdown = markdown
        self.style = style
        self.images = images
        self.isSelectable = isSelectable
        self.onLink = onLink
    }

    // MARK: - Body

    public var body: some View {
        let scheme: MarkdownColorScheme = (colorScheme == .dark) ? .dark : .light
        let doc = MarkdownRenderer.render(markdown, style: style, colorScheme: scheme)
        MarkdownTextView(doc, isSelectable: isSelectable, onLink: { handleLink($0) }, images: images)
    }

    // MARK: - Private

    private func handleLink(_ payload: LinkPayload) {
        switch MarkdownRenderer.resolveLink(payload.token) {
        case .url(let u):
            if let onLink {
                onLink(u)
            } else {
                openURL(u)
            }
        case .footnote, .ignore:
            break
        }
    }
}

// MARK: - Preview

private struct PreviewImageProvider: ImageProvider {
    func image(for source: String) async -> CGImage? {
        let w = 320, h = 213
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let band = CGFloat(h) / 3
        ctx.setFillColor(CGColor(red: 0.835, green: 0.169, blue: 0.118, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: band))
        ctx.setFillColor(CGColor(red: 0.0, green: 0.224, blue: 0.651, alpha: 1))
        ctx.fill(CGRect(x: 0, y: band, width: CGFloat(w), height: band))
        ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: band * 2, width: CGFloat(w), height: CGFloat(h) - band * 2))
        return ctx.makeImage()
    }
}

private let previewMarkdown = """
# Markdown Showcase

A paragraph with **bold**, *italic*, `inline code`, and a [Swift.org link](https://swift.org).

## Lists

- Apples
- Oranges
- **Bananas** (bold list item)

## Blockquote

> "The best way to predict the future is to invent it."
> — Alan Kay

## Table

| Column A | Column B | Column C |
|----------|----------|----------|
| one      | two      | three    |
| alpha    | beta     | gamma    |

## Code Block

```swift
struct ContentView: View {
    var body: some View {
        MarkdownView("# Hello, world!")
    }
}
```

![Sample image](sample)
"""

@available(iOS 26, macOS 14, *)
#Preview("MarkdownView") {
    ScrollView {
        MarkdownView(
            previewMarkdown,
            images: PreviewImageProvider(),
            isSelectable: false
        )
        .frame(maxWidth: 420)
        .padding()
    }
}

#endif
