/// Parses Markdown (CommonMark 0.31 + GFM + extended) into a value-type AST.
///
/// Supported: ATX/setext headings, paragraphs, fenced/indented code, block quotes (nested),
/// ordered/unordered/task lists (nested, tight/loose, lazy continuation), thematic breaks,
/// emphasis/strong, inline code, links/images (inline + reference), CommonMark autolinks,
/// GFM extended autolinks, strikethrough, hard/soft breaks, backslash escapes, GFM tables,
/// footnotes, definition lists. Code-block language is the info string only.
///
/// Out of scope (passed through as literal text): HTML blocks and inline HTML, character/entity
/// references, nested links, info strings containing backticks, and other rare CommonMark corners.
public enum MarkdownParser {
    public static func parse(_ source: String) -> MarkdownDocument {
        // Pass A: line preprocessing + block scan into raw leaves.
        let lines = splitIntoLines(source).map { expandTabs($0) }
        let defs = DefinitionStore()
        _ = BlockParser(defs: defs).parse(lines, depth: 0)

        // Pass B: resolve [RawBlock] into [MarkdownBlock] with parsed inlines.
        // Stub — lands in a later task. Until then `parse` returns an empty
        // document; end-to-end paragraph output arrives with Pass B.
        let blocks: [MarkdownBlock] = []
        let footnotes: [FootnoteDefinition] = []
        return MarkdownDocument(blocks: blocks, footnotes: footnotes)
    }
}
public struct MarkdownDocument: Equatable, Sendable, Hashable {
    public var blocks: [MarkdownBlock]
    public var footnotes: [FootnoteDefinition]
    public init(blocks: [MarkdownBlock], footnotes: [FootnoteDefinition]) { self.blocks = blocks; self.footnotes = footnotes }
}
