// Internal parse-time block tree (Pass A).
//
// `RawBlock` mirrors the public `MarkdownBlock` structure, but leaves hold the
// raw (un-inlined) text as `String`. Pass B (a later task) resolves these into
// the public `MarkdownBlock` AST with parsed inline content.
//
// These types are internal: they are parse-time structures, not part of the
// public API.

indirect enum RawBlock: Equatable {
    case heading(level: Int, raw: String)
    case paragraph(raw: String)
    case blockQuote(blocks: [RawBlock])
    case list(RawList)
    case codeBlock(language: String?, code: String)
    case thematicBreak
    case table(RawTable)
    case definitionList([RawDefinition])
}

struct RawList: Equatable {
    var kind: MarkdownList.Kind
    var isTight: Bool
    var items: [RawListItem]
}

struct RawListItem: Equatable {
    var blocks: [RawBlock]
    var task: TaskState?
}

struct RawTable: Equatable {
    var alignments: [MarkdownTable.Alignment]
    var header: [[String]]
    var rows: [[String]]
}

struct RawDefinition: Equatable {
    var term: String
    var details: [[RawBlock]]
}
