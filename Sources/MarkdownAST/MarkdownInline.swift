public indirect enum MarkdownInline: Equatable, Sendable, Hashable {
    case text(String)
    case emphasis([MarkdownInline])
    case strong([MarkdownInline])
    case strikethrough([MarkdownInline])
    case code(String)
    case link(destination: String, title: String?, content: [MarkdownInline])
    case image(source: String, title: String?, alt: String)
    case autolink(url: String)
    case footnoteReference(id: String)
    case softBreak
    case hardBreak
}