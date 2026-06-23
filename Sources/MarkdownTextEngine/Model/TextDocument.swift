import CoreGraphics

public struct TextDocument: Equatable, Sendable {
    public var blocks: [Block]
    public init(blocks: [Block]) { self.blocks = blocks }
}

public indirect enum Block: Equatable, Sendable {
    case paragraph(Paragraph)
    case list(List)
    case quote(TextDocument)
    case table(Table)
    case codeBlock(CodeBlock)
    case image(ImageAttachment)
    case thematicBreak(RuleStyle)
}

public struct Paragraph: Equatable, Sendable {
    public var runs: [InlineRun]; public var style: ParagraphStyle
    public init(runs: [InlineRun], style: ParagraphStyle) { self.runs = runs; self.style = style }
}

public enum ListMarkerStyle: Equatable, Sendable { case bullet, ordered(start: Int) }

public struct List: Equatable, Sendable {
    public var marker: ListMarkerStyle; public var isTight: Bool; public var items: [TextDocument]
    public init(marker: ListMarkerStyle, isTight: Bool, items: [TextDocument]) {
        self.marker = marker; self.isTight = isTight; self.items = items
    }
}

public struct Table: Equatable, Sendable {
    public var alignments: [TextAlignment]
    public var header: [[InlineRun]]
    public var rows: [[[InlineRun]]]
    public var cellStyle: TextStyle
    public init(alignments: [TextAlignment], header: [[InlineRun]], rows: [[[InlineRun]]], cellStyle: TextStyle) {
        self.alignments = alignments; self.header = header; self.rows = rows; self.cellStyle = cellStyle
    }
}

public struct CodeBlock: Equatable, Sendable {
    public var lines: [String]; public var language: String?; public var style: TextStyle
    public init(lines: [String], language: String?, style: TextStyle) {
        self.lines = lines; self.language = language; self.style = style
    }
}
