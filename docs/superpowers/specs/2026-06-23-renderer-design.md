# Spec 3 — Markdown Renderer (`Marked`) Design

**Status:** approved design (2026-06-23)
**Depends on:** Spec 1 `MarkdownAST` (parser, done), Spec 2 `MarkdownTextEngine` (text engine, done)

## Goal

Make the library usable from a raw Markdown **string**. Today the engine renders
a hand-built `TextDocument`; this spec adds the missing glue: parse Markdown →
map the `MarkdownAST` to the engine's `TextDocument` under a single style config,
and expose a one-line SwiftUI view. This is the third and final spec.

## Scope (v1)

Full coverage of what the parser produces. Most AST nodes map cleanly because the
engine already supports paragraphs, lists, quotes, GFM tables, code blocks,
images, thematic breaks, links, and all inline styles natively. The renderer also
handles the AST features the engine has **no** native equivalent for: headings
(→ styled paragraphs), **task checkboxes**, **footnotes**, and **definition
lists**.

Out of scope (v2): custom font families, footnote tap-to-scroll (engine has no
anchors), styling the quote bar / code-box tint / list-marker color (engine
draws these with hardcoded defaults).

---

## 1. Architecture

New module **`Marked`** (SwiftPM target in `swift-marked`), depending on
`MarkdownAST` + `MarkdownTextEngine`, with `@_exported import` of both so a
consumer writes `import Marked` and gets the parser, the engine, and the new
renderer/view. `Marked` is Apple-only (it depends on the Apple-only engine);
the Linux CI guard remains `MarkdownAST`-only.

Three layers (mirroring the engine's pure-core + platform-shell split):

1. **Pure core — `MarkdownRenderer`** (no UIKit/SwiftUI; imports only the AST
   models, the engine models, and `MarkdownStyle`). Recursively maps AST blocks
   and inline nodes to a `TextDocument`. Fully deterministic and unit-testable.
2. **Style config — `MarkdownStyle`** (value type, `Sendable`, `.default`).
3. **Platform shell — `MarkdownView`** (SwiftUI `View`, behind
   `#if canImport(SwiftUI)`). Parses the string, watches environment
   (`colorScheme`, `openURL`), calls `render`, and hosts the engine's
   `MarkdownTextView`.

Files under `Sources/Marked/`: `Marked.swift` (re-exports), `MarkdownRenderer.swift`,
`InlineMapper.swift`, `BlockMapper.swift`, `MarkdownStyle.swift`, `MarkdownView.swift`.

## 2. Mapping (AST → TextDocument)

### Inline (`[MarkdownInline]` → `[InlineRun]`)

Recursive flatten with an accumulated `TextStyle` (copy-and-modify on descent):

| AST inline | → InlineRun |
|---|---|
| `.text(s)` | `.text(s, style)` |
| `.emphasis(children)` | recurse, `isItalic = true` |
| `.strong(children)` | recurse, `isBold = true` |
| `.strikethrough(children)` | recurse, `isStrikethrough = true` |
| `.code(s)` | `.text(s, style{isMonospace, codeColor, codeFontSize})` |
| `.link(dest,_,content)` | `.link(runs: map(content, linkColor), payload: LinkPayload(dest))` |
| `.image(src,_,alt)` | `.inlineImage(ImageAttachment(src, style.inlineImageSize, alt))` |
| `.autolink(url)` | `.link(runs: [.text(url, linkColor)], payload: LinkPayload(url))` |
| `.footnoteReference(id)` | `.link(runs: [.text("[n]", footnoteRefStyle)], payload: LinkPayload("footnote:\(id)"))` |
| `.softBreak` | `" "` (a space — CommonMark renders a soft break as a space) |
| `.hardBreak` | `.lineBreak(hard: true)` |

Nested wrappers compose (strong+emphasis → bold+italic). Adjacent runs with an
equal `TextStyle` are merged. Footnote numbers `n` come from the order of
`document.footnotes` (1-based).

### Block (`mapBlocks([MarkdownBlock]) -> [Block]`, one→many allowed)

| AST block | → engine Block(s) |
|---|---|
| `.heading(level, content)` | `.paragraph` with the h-level `TextStyle` (size = `headingSizes[level-1]`, bold) and heading spacing |
| `.paragraph(content)` | `.paragraph` (body style) |
| `.blockQuote(blocks)` | `.quote(TextDocument(blocks: mapBlocks(blocks)))` (recursive) |
| `.list(list)` | `.list(List(marker: kind→ListMarkerStyle, isTight, items: list.items.map { TextDocument(blocks: mapBlocks($0.blocks)) }))` |
| `.codeBlock(lang, code)` | `.codeBlock(CodeBlock(lines: code split on "\n", language: lang, style: codeStyle))` |
| `.thematicBreak` | `.thematicBreak(RuleStyle(color: ruleColor))` |
| `.table(table)` | `.table(Table(alignments: map, header/rows: cells→[InlineRun], cellStyle: body))` — `.none`/`.left`→`.leading`, `.center`→`.center`, `.right`→`.trailing` |
| `.definitionList(defs)` | **multiple blocks** per entry: term → `.paragraph` (bold); each detail → `mapBlocks` with `leadingIndent = spacing.definitionIndent` |

### Special features

- **Task checkboxes:** a `MarkdownListItem` with `task != nil` prepends a
  `"☑ "` / `"☐ "` run to its first paragraph's runs (list marker stays bullet).
- **Footnotes** (document-level): after the body blocks, if
  `document.footnotes` is non-empty, append a `.thematicBreak`, a small
  "Footnotes" heading (secondary color, `footnoteFontSize`), then one entry per
  footnote: a paragraph `"n. "` + the footnote's mapped block content.
- **Lone-image promotion:** a paragraph whose content is a single `.image`
  (ignoring surrounding whitespace text) becomes a block `.image`
  (`intrinsicSize = style.blockImage`); otherwise the image stays inline.

### Document & color scheme

`render(_ document:, style:, colorScheme:)` = `mapBlocks(document.blocks)` +
footnotes section. The `colorScheme` selects `style.light` or `style.dark`,
whose colors become the concrete `CGColor`s in every `TextStyle`. The view
re-renders when the scheme or style changes.

## 3. `MarkdownStyle`

```swift
public struct MarkdownStyle: Sendable {
    public var baseFontSize: CGFloat        // body, default 17
    public var headingSizes: [CGFloat]      // h1…h6, default [28,23,19,17,15,14] (bold)
    public var codeFontSize: CGFloat        // default 14 (monospace)
    public var footnoteFontSize: CGFloat    // refs + footnotes section, default 13
    public var inlineImageSize: CGSize      // inline image reservation, default 18×18
    public var blockImage: CGSize           // lone-image block reservation, default 320×180
    public var light: Palette
    public var dark: Palette
    public var spacing: Spacing
    public static let `default`: MarkdownStyle

    public struct Palette: Sendable {        // semantic colors
        public var text, secondary, link, code, rule: CGColor
    }
    public struct Spacing: Sendable {
        // Only fields the engine can apply via ParagraphStyle:
        // paragraphAfter → spacingAfter; heading* → heading paragraph spacing;
        // definitionIndent → leadingIndent on detail paragraphs.
        public var paragraphAfter, headingBefore, headingAfter, definitionIndent: CGFloat
    }
}
```

Defaults — light: text `#1E1E20`, secondary `#6E6E78`, link `#0A6CF5`,
code `#5A5A66`, rule `#CCCCD2`; dark: symmetric light values on dark.
Fonts are system SF (+ SF Mono for code) — the engine builds `CTFont` from size
and flags; there is no font-family field. Custom fonts are deferred (v2).

The renderer centralizes style resolution in helpers that build the
`TextStyle`/`ParagraphStyle` for each element (body, heading[level], code,
inline-code, link, footnote) from the active `Palette`.

## 4. Public API

```swift
// Pure core (no SwiftUI):
public enum MarkdownRenderer {
    static func render(_ document: MarkdownDocument,
                       style: MarkdownStyle = .default,
                       colorScheme: MarkdownColorScheme = .light) -> TextDocument
    static func render(_ markdown: String,                  // parse + render (both total)
                       style: MarkdownStyle = .default,
                       colorScheme: MarkdownColorScheme = .light) -> TextDocument
}
public enum MarkdownColorScheme: Sendable { case light, dark }

// SwiftUI entry (#if canImport(SwiftUI)):
public struct MarkdownView: View {
    public init(_ markdown: String,
                style: MarkdownStyle = .default,
                images: (any ImageProvider)? = nil,
                isSelectable: Bool = true,
                onLink: ((URL) -> Void)? = nil)
}
```

`MarkdownView`: parses the string (memoized — re-parse only when `markdown`
changes); reads `@Environment(\.colorScheme)` and `\.openURL`; calls `render`;
feeds the `TextDocument` to `MarkdownTextEngine.MarkdownTextView`. A
scheme/style change re-renders and re-lays-out.

**Links:** the engine yields `LinkPayload(token)`. `resolveLink(token:)` (pure,
testable) returns `.url(URL)`, `.footnote(id)`, or `.ignore`. For `.url`: call
the consumer's `onLink` if provided, else `openURL`. `.footnote` is a no-op in
v1 (no anchors). A nil `URL(string:)` → `.ignore`.

**Images:** the consumer's `ImageProvider` (re-exported from the engine) is
passed straight through; sizes are reserved from `style` (the engine fits to
width and loads asynchronously).

**Errors:** none by contract — the parser and `render` are total (malformed
Markdown → best-effort text), and nil URLs are skipped. No throws, no crashes.

## 5. Testing

The pure core is fully TDD-covered (`TextDocument`/`Block`/`InlineRun` are
`Equatable`, so tests assert result structure):

- **Inline rules** — one test each: emphasis→italic, strong→bold,
  nested strong+emphasis→both, strikethrough, code→mono+codeColor,
  link→`.link` with `payload == dest`, autolink, image→`.inlineImage`,
  footnoteRef→`footnote:` link, hardBreak→`.lineBreak(true)`, softBreak→space,
  adjacent-run merge.
- **Block rules** — heading level→size+bold, paragraph, blockQuote→recursive
  `.quote`, list (bullet/ordered/tight), task→checkbox prefix, codeBlock→lines+
  language, thematicBreak, table→alignment mapping + cells, definitionList→
  term(bold)+indented details.
- **Document level** — footnotes → appended section; lone-image paragraph →
  block `.image`.
- **Style / colorScheme** — a custom `MarkdownStyle` is reflected in sizes/
  colors; light vs dark → different `CGColor`s.
- **End-to-end** — `render(String)` golden cases (Markdown string → asserted
  `TextDocument`).
- **`resolveLink`** — `.url` / `.footnote` / `.ignore`.

The SwiftUI `MarkdownView` (thin glue) is not headless-unit-testable; it is
compile-verified on iOS + macOS and checked by reading + `#Preview`.

Infra: new target `Marked` (deps `MarkdownAST` + `MarkdownTextEngine`) + test
target `MarkedTests` (Swift Testing). Covered by the macOS CI job.

## 6. Wave decomposition

- **Wave 0 — Scaffolding.** Add `Marked` + `MarkedTests` targets to
  `Package.swift`; `Marked.swift` (`@_exported import`s); `MarkdownColorScheme`;
  empty `MarkdownRenderer`/`MarkdownStyle` skeletons. Build green.
- **Wave 1 — `MarkdownStyle`.** Fields, `.default`, light/dark palettes, and the
  per-element `TextStyle`/`ParagraphStyle` resolution helpers. TDD.
- **Wave 2 — Inline mapping.** `InlineMapper`: every `MarkdownInline` →
  `[InlineRun]` with style accumulation + run merging. TDD (the inline table).
- **Wave 3 — Block mapping.** `BlockMapper`: heading/paragraph/quote/list/code/
  thematicBreak/table. TDD.
- **Wave 4 — Special features.** Task checkboxes, definition lists, footnotes
  section, lone-image→block promotion. TDD.
- **Wave 5 — `MarkdownRenderer`.** Top-level `render(document)` +
  `render(String)` + `resolveLink` + colorScheme selection; golden end-to-end
  cases. TDD.
- **Wave 6 — `MarkdownView`.** SwiftUI glue: parse memo, `colorScheme`/`openURL`
  environment, host `MarkdownTextView`, `onLink`, `images`, `#Preview`.
  Compile-verified iOS + macOS.
- **Wave 7 — Final gate.** README/docs update (third module, `import Marked`
  example), build/test/lint green on macOS + iOS, known-gaps documented.

## 7. Known v1 gaps (documented, not blocking)

- Footnote references are clickable but do not scroll to the note (no engine
  anchors); the notes are appended at the end.
- Quote-bar color, code-box background tint, and list-marker color/size use the
  engine's hardcoded defaults — not yet driven by `MarkdownStyle` (small engine
  follow-ups).
- List/quote indentation is engine-controlled (marker width / bar inset), and
  non-paragraph blocks (table/code/image) get no inter-block spacing — both are
  engine gaps (Wave-5 deferred minor), so `MarkdownStyle.Spacing` does not expose
  them.
- Custom font families are deferred; system SF / SF Mono only.
- `softBreak` renders as a space (not a forced line break).
