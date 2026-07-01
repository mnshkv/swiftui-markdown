import Foundation
import CoreGraphics

/// Maps a `MarkdownDocument` (AST) to a `TextDocument` (text engine). Filled in Wave 1.
public enum MarkdownRenderer {}

// MARK: - Task 5.1: top-level render + footnotes

public extension MarkdownRenderer {

    /// Renders a `MarkdownDocument` AST into a `TextDocument` using the given style and color scheme.
    /// Always returns a valid document; never throws or crashes, including on duplicate footnote ids.
    static func render(
        _ document: MarkdownDocument,
        style: MarkdownStyle = .default,
        colorScheme: MarkdownColorScheme = .light,
        rules: [InlineRule] = []
    ) -> TextDocument {
        // Build footnote number map safely — duplicate ids overwrite (last-wins), no crash.
        var footnoteNumbers: [String: Int] = [:]
        for (i, fn) in document.footnotes.enumerated() {
            footnoteNumbers[fn.id] = i + 1
        }

        let ctx = StyleContext(style, colorScheme, rules: rules)
        var blocks = BlockMapper.map(document.blocks, ctx: ctx, footnotes: footnoteNumbers)

        // Append footnotes section if there are any footnotes.
        if !document.footnotes.isEmpty {
            // 1. Thematic break separator
            blocks.append(.thematicBreak(RuleStyle(color: ctx.palette.rule)))

            // 2. "Footnotes" header paragraph (bold footnote style)
            var boldFootnote = ctx.footnote
            boldFootnote.isBold = true
            blocks.append(.paragraph(Paragraph(
                runs: [.text("Footnotes", boldFootnote)],
                style: ctx.bodyParagraph
            )))

            // 3. Per-footnote: numbered label paragraph + indented content blocks
            for (i, fn) in document.footnotes.enumerated() {
                let n = i + 1

                // "n. " label paragraph
                blocks.append(.paragraph(Paragraph(
                    runs: [.text("\(n). ", ctx.footnote)],
                    style: ctx.bodyParagraph
                )))

                // Footnote body blocks, each indented by definitionIndent
                let fnBlocks = BlockMapper.map(fn.blocks, ctx: ctx, footnotes: footnoteNumbers)
                for block in fnBlocks {
                    blocks.append(BlockMapper.indent(block, by: style.spacing.definitionIndent))
                }
            }
        }

        return TextDocument(blocks: blocks)
    }

    /// Parses `markdown` and renders it using the given style and color scheme.
    ///
    /// This is the convenience entry point used by `MarkdownView`. It calls
    /// `MarkdownParser.parse` then delegates to the `MarkdownDocument` overload.
    ///
    /// ## v1 Known Limitations (Spec §7)
    ///
    /// - **Footnote refs** — `[^ref]` tokens resolve to `.footnote(id)` via
    ///   `resolveLink`, but `MarkdownView` does **not** scroll to the footnote
    ///   body; scrolling to anchors is deferred.
    /// - **Engine-default colours** — quote bar, code-box tint, and list-marker
    ///   colour come from `MarkdownTextEngine` built-ins; `MarkdownStyle` does
    ///   not control them.
    /// - **System fonts only** — custom font families are not supported; weight,
    ///   size, and monospaced traits are used to select system fonts.
    /// - **`softBreak` → space** — soft line breaks in the Markdown source are
    ///   emitted as a single space run in the `TextDocument`.
    static func render(
        _ markdown: String,
        style: MarkdownStyle = .default,
        colorScheme: MarkdownColorScheme = .light,
        rules: [InlineRule] = []
    ) -> TextDocument {
        render(MarkdownParser.parse(markdown), style: style, colorScheme: colorScheme, rules: rules)
    }
}

// MARK: - Task 5.2: LinkAction + resolveLink

/// The action to take when a link token is activated.
public enum LinkAction: Equatable {
    case url(URL)
    case footnote(String)
    case custom(ruleID: String, value: String)
    case ignore
}

public extension MarkdownRenderer {

    /// Resolves a link token string into a `LinkAction`.
    ///
    /// - Tokens starting with `"footnote:"` become `.footnote(id)`.
    /// - All other non-empty tokens are parsed by `URL(string:)`:
    ///   valid URL → `.url`; nil or empty → `.ignore`.
    static func resolveLink(_ token: String) -> LinkAction {
        if let (ruleID, value) = InlineRuleToken.decode(token) {
            return .custom(ruleID: ruleID, value: value)
        }
        let footnotePrefix = "footnote:"
        if token.hasPrefix(footnotePrefix) {
            return .footnote(String(token.dropFirst(footnotePrefix.count)))
        }
        guard !token.isEmpty, let url = URL(string: token) else {
            return .ignore
        }
        return .url(url)
    }
}
