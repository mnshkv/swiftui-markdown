import CoreGraphics

/// Resolves per-element `TextStyle` and `ParagraphStyle` values for a given
/// `MarkdownStyle` + color scheme. Internal — consumed by block/inline mappers.
struct StyleContext {

    let style: MarkdownStyle
    let palette: MarkdownStyle.Palette

    init(_ style: MarkdownStyle, _ scheme: MarkdownColorScheme) {
        self.style = style
        self.palette = scheme == .light ? style.light : style.dark
    }

    // MARK: - Text styles

    var body: TextStyle {
        TextStyle(fontSize: style.baseFontSize, color: palette.text)
    }

    func heading(_ level: Int) -> TextStyle {
        let clamped = max(1, min(6, level))
        return TextStyle(
            fontSize: style.headingSizes[clamped - 1],
            isBold: true,
            color: palette.text
        )
    }

    var inlineCode: TextStyle {
        TextStyle(fontSize: style.codeFontSize, isMonospace: true, color: palette.code)
    }

    var codeBlock: TextStyle {
        TextStyle(fontSize: style.codeFontSize, isMonospace: true, color: palette.code)
    }

    var footnote: TextStyle {
        TextStyle(fontSize: style.footnoteFontSize, color: palette.secondary)
    }

    func linkColored(_ base: TextStyle) -> TextStyle {
        var t = base
        t.color = palette.link
        return t
    }

    // MARK: - Paragraph styles

    var bodyParagraph: ParagraphStyle {
        ParagraphStyle(spacingAfter: style.spacing.paragraphAfter)
    }

    func headingParagraph() -> ParagraphStyle {
        ParagraphStyle(
            spacingBefore: style.spacing.headingBefore,
            spacingAfter: style.spacing.headingAfter
        )
    }

    func indentedParagraph(_ indent: CGFloat) -> ParagraphStyle {
        ParagraphStyle(
            spacingAfter: style.spacing.paragraphAfter,
            leadingIndent: indent
        )
    }
}
