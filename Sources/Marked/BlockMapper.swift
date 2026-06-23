import CoreGraphics

enum BlockMapper {

    static func map(
        _ mdBlocks: [MarkdownBlock],
        ctx: StyleContext,
        footnotes: [String: Int]
    ) -> [Block] {
        var blocks: [Block] = []
        for block in mdBlocks {
            switch block {
            case .heading(let level, let content):
                blocks.append(.paragraph(Paragraph(
                    runs: InlineMapper.map(content, base: ctx.heading(level), ctx: ctx, footnotes: footnotes),
                    style: ctx.headingParagraph()
                )))
            case .paragraph(let content):
                if let lone = loneImage(content) {
                    blocks.append(.image(ImageAttachment(
                        source: lone.source,
                        intrinsicSize: ctx.style.blockImage,
                        alt: lone.alt
                    )))
                } else {
                    blocks.append(.paragraph(Paragraph(
                        runs: InlineMapper.map(content, base: ctx.body, ctx: ctx, footnotes: footnotes),
                        style: ctx.bodyParagraph
                    )))
                }
            case .blockQuote(let inner):
                blocks.append(.quote(TextDocument(blocks: map(inner, ctx: ctx, footnotes: footnotes))))
            case .codeBlock(let lang, let code):
                blocks.append(.codeBlock(CodeBlock(
                    lines: code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
                    language: lang,
                    style: ctx.codeBlock
                )))
            case .thematicBreak:
                blocks.append(.thematicBreak(RuleStyle(color: ctx.palette.rule)))
            case .table(let t):
                let alignments = t.alignments.map(mapAlignment)
                let header = t.header.map { cell in
                    InlineMapper.map(cell, base: ctx.body, ctx: ctx, footnotes: footnotes)
                }
                let rows = t.rows.map { row in
                    row.map { cell in
                        InlineMapper.map(cell, base: ctx.body, ctx: ctx, footnotes: footnotes)
                    }
                }
                blocks.append(.table(Table(
                    alignments: alignments,
                    header: header,
                    rows: rows,
                    cellStyle: ctx.body
                )))
            case .list(let list):
                let marker: ListMarkerStyle = {
                    switch list.kind {
                    case .bullet: return .bullet
                    case .ordered(let s): return .ordered(start: s)
                    }
                }()
                let items = list.items.map { item in
                    var itemBlocks = map(item.blocks, ctx: ctx, footnotes: footnotes)
                    if let task = item.task {
                        itemBlocks = prependCheckbox(task, to: itemBlocks, ctx: ctx)
                    }
                    return TextDocument(blocks: itemBlocks)
                }
                blocks.append(.list(List(marker: marker, isTight: list.isTight, items: items)))
            case .definitionList(let defs):
                for d in defs {
                    var termStyle = ctx.body
                    termStyle.isBold = true
                    blocks.append(.paragraph(Paragraph(
                        runs: InlineMapper.map(d.term, base: termStyle, ctx: ctx, footnotes: footnotes),
                        style: ctx.bodyParagraph
                    )))
                    for detail in d.details {
                        for b in map(detail, ctx: ctx, footnotes: footnotes) {
                            blocks.append(indent(b, by: ctx.style.spacing.definitionIndent))
                        }
                    }
                }
            }
        }
        return blocks
    }

    // MARK: - Private helpers

    private static func prependCheckbox(_ task: TaskState, to itemBlocks: [Block], ctx: StyleContext) -> [Block] {
        let glyph = task == .checked ? "☑ " : "☐ "
        let checkboxRun = InlineRun.text(glyph, ctx.body)
        var result = itemBlocks
        if let idx = result.firstIndex(where: { if case .paragraph = $0 { return true }; return false }) {
            guard case .paragraph(var p) = result[idx] else { return result }
            p.runs.insert(checkboxRun, at: 0)
            result[idx] = .paragraph(p)
        } else {
            let p = Paragraph(runs: [checkboxRun], style: ctx.bodyParagraph)
            result.insert(.paragraph(p), at: 0)
        }
        return result
    }

    private static func indent(_ block: Block, by amount: CGFloat) -> Block {
        guard case .paragraph(var p) = block else { return block }
        p.style.leadingIndent += amount
        return .paragraph(p)
    }

    /// Returns `(source, alt)` if `content` contains exactly one `.image` and all
    /// other nodes are whitespace-only `.text` or `.softBreak`. Returns `nil` otherwise.
    private static func loneImage(_ content: [MarkdownInline]) -> (source: String, alt: String)? {
        var found: (source: String, alt: String)?
        for node in content {
            switch node {
            case .image(let src, _, let alt):
                if found != nil { return nil }  // more than one image
                found = (src, alt)
            case .text(let s) where s.allSatisfy(\.isWhitespace):
                break  // whitespace-only text is ignored
            case .softBreak:
                break
            default:
                return nil  // non-whitespace content → not a lone image
            }
        }
        return found
    }

    private static func mapAlignment(_ alignment: MarkdownTable.Alignment) -> TextAlignment {
        switch alignment {
        case .none, .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}
