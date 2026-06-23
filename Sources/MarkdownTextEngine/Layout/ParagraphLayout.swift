import CoreText

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
