public indirect enum MarkdownBlock: Equatable, Sendable, Hashable {
    case heading(level: Int, content: [MarkdownInline])
    case paragraph(content: [MarkdownInline])
    case blockQuote(blocks: [MarkdownBlock])
    case list(MarkdownList)
    case codeBlock(language: String?, code: String)
    case thematicBreak
    case table(MarkdownTable)
    case definitionList([MarkdownDefinition])
}
public struct MarkdownList: Equatable, Sendable, Hashable {
    public enum Kind: Equatable, Sendable, Hashable { case bullet; case ordered(start: Int) }
    public var kind: Kind; public var isTight: Bool; public var items: [MarkdownListItem]
    public init(kind: Kind, isTight: Bool, items: [MarkdownListItem]) { self.kind = kind; self.isTight = isTight; self.items = items }
}
public struct MarkdownListItem: Equatable, Sendable, Hashable {
    public var blocks: [MarkdownBlock]; public var task: TaskState?
    public init(blocks: [MarkdownBlock], task: TaskState? = nil) { self.blocks = blocks; self.task = task }
}
public enum TaskState: Equatable, Sendable, Hashable { case checked, unchecked }
public struct MarkdownTable: Equatable, Sendable, Hashable {
    public enum Alignment: Equatable, Sendable, Hashable { case none, left, center, right }
    public var alignments: [Alignment]; public var header: [[MarkdownInline]]; public var rows: [[[MarkdownInline]]]
    public init(alignments: [Alignment], header: [[MarkdownInline]], rows: [[[MarkdownInline]]]) { self.alignments = alignments; self.header = header; self.rows = rows }
}
public struct MarkdownDefinition: Equatable, Sendable, Hashable {
    public var term: [MarkdownInline]; public var details: [[MarkdownBlock]]
    public init(term: [MarkdownInline], details: [[MarkdownBlock]]) { self.term = term; self.details = details }
}
public struct FootnoteDefinition: Equatable, Sendable, Hashable {
    public var id: String; public var blocks: [MarkdownBlock]
    public init(id: String, blocks: [MarkdownBlock]) { self.id = id; self.blocks = blocks }
}