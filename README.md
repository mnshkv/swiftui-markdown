# swiftui-markdown

A hand-written SwiftUI Markdown library, built in pure Swift with **no
third-party dependencies**. It ships as two layers you can use independently:

- **`MarkdownAST`** — a zero-dependency parser that turns Markdown (CommonMark
  0.31 + GFM + extensions) into a value-type AST. No `swift-markdown`, no
  Foundation in the parser core.
- **`MarkdownTextEngine`** — a read-only CoreText typesetter that lays out,
  draws, and selects a generic rich-text document, hosted in SwiftUI via a
  `MarkdownTextView`. Apple frameworks only (CoreText / Core Graphics / SwiftUI
  / UIKit·AppKit).

Built test-first (TDD): every feature is driven by a failing test, and the suite
currently has **469 tests** across the two modules (0 lint errors).

## Installation

Swift Package Manager — both products are available:

```swift
.package(url: "https://github.com/mnshkv/swiftui-markdown.git", branch: "main")
// .product(name: "MarkdownAST", package: "swiftui-markdown")          // parser
// .product(name: "MarkdownTextEngine", package: "swiftui-markdown")   // text engine
```

Requires Swift 6.2+. `MarkdownAST` is platform-agnostic (builds on Linux);
`MarkdownTextEngine` targets iOS 26+ and macOS.

## Usage

### Parse Markdown into an AST

```swift
import MarkdownAST

let doc = MarkdownParser.parse("# Hello\n\nWorld with **bold** and `code`.")
// doc.blocks == [
//   .heading(level: 1, content: [.text("Hello")]),
//   .paragraph(content: [.text("World with "), .strong([.text("bold")]),
//                        .text(" and "), .code("code"), .text(".")]),
// ]
```

`MarkdownParser.parse` returns a `MarkdownDocument` (`blocks: [MarkdownBlock]`,
`footnotes: [FootnoteDefinition]`). The AST types are plain `enum`/`struct`
values (`Equatable`, `Sendable`, `Hashable`).

### Display it (text engine)

The engine is Markdown-agnostic: it renders a generic `TextDocument`. A future
renderer (Spec 3, below) will map `MarkdownAST` → `TextDocument` for you; until
then you build the `TextDocument` yourself.

```swift
import MarkdownTextEngine

MarkdownTextView(
    textDocument,                 // a generic TextDocument (blocks + styled runs)
    isSelectable: true,
    onLink: { payload in /* openURL(...) */ },
    images: myImageProvider       // async CGImage loading
)
```

The engine draws everything itself — text, lists, quotes, GFM tables, code
blocks, images, rules — in one unified layout, so a single selection is
continuous across the whole document.

## How it works

**Parser** — two passes:

1. **Pass A — block structure.** Splits the source into lines (tabs expanded,
   `\n`/`\r\n`/`\r` handled), scans block constructs into a raw tree, and
   collects all link-reference and footnote definitions.
2. **Pass B — inline resolution.** Once every definition is known, each raw leaf
   is parsed into inline nodes — so references defined *after* their use still
   resolve.

**Text engine** — three layers: a pure, TDD-tested core (model + layout +
selection + a thin Core Graphics renderer) and a platform shell (`UIView`/
`NSView` + a SwiftUI representable) behind `#if`. Full layout once + windowed
drawing. The document-wide selection index space is UTF-16 throughout, kept in
sync across every block type by construction.

## Status

### Parser (`MarkdownAST`) — CommonMark + GFM

**Blocks:** ATX & setext headings · paragraphs · fenced & indented code ·
block quotes (nested, lazy continuation) · thematic breaks · GFM tables ·
lists (bullet/ordered, nested, tight/loose, GFM task items `[ ]`/`[x]`) ·
definition lists · link-reference & footnote definitions.

**Inline:** text · backslash escapes · code spans · emphasis / strong (canonical
`process_emphasis`, rule of 3) · GFM strikethrough · inline & reference links
and images · CommonMark autolinks · GFM extended bare autolinks (URLs & emails) ·
hard / soft breaks · footnote references.

**Conformance:** **505 / 652 (77.5%)** of the official CommonMark 0.31.2 spec
examples pass, verified by a parameterized harness (AST → HTML vs. normalized
spec HTML). Out of scope by design (passed through as literal text): raw
HTML blocks / inline HTML and character/entity references.

### Text engine (`MarkdownTextEngine`) — read-only

Unified layout + drawing of paragraphs, headings, lists, quotes, GFM tables,
code blocks, block & inline images, thematic breaks; document-wide selection,
hit-testing, copy, word selection; link tap + pressed highlight; async image
loading via an `ImageProvider`; native selection affordances.

Documented v1 limitations: links inside block quotes / list items are not yet
tap/highlight-reachable; full selection loupe deferred (handle knobs only); RTL
deferred (LTR only); horizontal code scrolling deferred (long lines wrap);
layout virtualization deferred (full layout + windowed draw); rich/Markdown copy
deferred (plain text only).

### Roadmap

The library is three specs, built in dependency order:

1. **Parser → AST** (`MarkdownAST`) — ✅ done.
2. **Text engine** (`MarkdownTextEngine`) — ✅ done.
3. **Markdown renderer** — *next*: binds `MarkdownAST` + the engine (maps the AST
   to a `TextDocument`, wires `openURL` and image loading, a single style config).

## Development

```sh
swift build      # build
swift test       # run the test suite (469 tests)
swiftlint        # lint (config in .swiftlint.yml)
```

CI (GitHub Actions) on every push and pull request: full build + test on macOS
(the engine needs Apple frameworks), a Linux build guard for the
zero-dependency `MarkdownAST` target, and SwiftLint.

## License

[MIT](LICENSE) — do whatever you want with it.
