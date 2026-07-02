# swift-marked

A hand-written SwiftUI Markdown library, built in pure Swift with **no
third-party dependencies**. It ships as three layers you can use independently:

- **`MarkdownAST`** — a zero-dependency parser that turns Markdown (CommonMark
  0.31 + GFM + extensions) into a value-type AST. No `swift-markdown`, no
  Foundation in the parser core.
- **`MarkdownTextEngine`** — a read-only CoreText typesetter that lays out,
  draws, and selects a generic rich-text document, hosted in SwiftUI via a
  `MarkdownTextView`. Apple frameworks only (CoreText / Core Graphics / SwiftUI
  / UIKit·AppKit).
- **`Marked`** — the umbrella renderer module. It `@_exported`-re-exports both
  the parser and the engine, maps a `MarkdownDocument` AST to a `TextDocument`,
  and wraps everything in a single `MarkdownView` SwiftUI view. A single
  `import Marked` is all you need.

Built test-first (TDD): every feature is driven by a failing test, and the suite
currently has **558 tests** across all three modules (0 lint errors).

## Installation

Swift Package Manager — all three products are available:

```swift
.package(url: "https://github.com/mnshkv/swift-marked.git", branch: "main")
// .product(name: "Marked", package: "swift-marked")               // umbrella renderer (recommended)
// .product(name: "MarkdownAST", package: "swift-marked")          // parser only
// .product(name: "MarkdownTextEngine", package: "swift-marked")   // text engine only
```

Requires Swift 6.2+. `MarkdownAST` is platform-agnostic (builds on Linux);
`MarkdownTextEngine` and `Marked` target iOS 17+ and macOS 14+.

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

### Render Markdown in SwiftUI (recommended)

One import, one view — `Marked` re-exports the parser and engine:

```swift
import Marked

struct ContentView: View {
    var body: some View {
        MarkdownView("# Hello\n\nWorld with **bold** and a [link](https://swift.org).")
    }
}
```

Links are opened via the SwiftUI environment's `openURL` action by default, or
you can supply an `onLink: (URL) -> Void` closure. Images are loaded
asynchronously via an `ImageProvider` you provide.

### Customizing the style

`MarkdownStyle` is a plain value type with public, mutable fields. The easiest
way to customize is to start from `.default` and change only what you need, then
pass it to `MarkdownView(_:style:)`:

```swift
import Marked

var style = MarkdownStyle.default

style.baseFontSize = 16                       // body text size
style.headingSizes = [30, 24, 20, 17, 15, 14] // h1…h6 (always 6 values)
style.codeFontSize = 13                        // monospace code
style.spacing.paragraphAfter = 12              // gap below paragraphs
style.spacing.headingBefore = 18

// Colors are CGColor; light and dark are independent palettes.
style.light.link = CGColor(srgbRed: 0.80, green: 0.20, blue: 0.20, alpha: 1) // brand red
style.dark.link  = CGColor(srgbRed: 1.00, green: 0.45, blue: 0.45, alpha: 1)
style.light.text = CGColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1)

MarkdownView(markdownString, style: style)
```

The renderer picks `style.light` or `style.dark` automatically from the
SwiftUI `\.colorScheme` environment and re-renders on change.

**Fields:** `baseFontSize`, `headingSizes` (6 values, h1–h6, rendered bold),
`codeFontSize`, `footnoteFontSize`, `inlineImageSize`, `blockImage` (reserved
size for a standalone image), `light` / `dark` palettes
(`text` · `secondary` · `link` · `code` · `rule`), and `spacing`
(`paragraphAfter` · `headingBefore` · `headingAfter` · `definitionIndent`).

You can also build a `MarkdownStyle` from scratch with its memberwise
initializer if you prefer not to derive from `.default`.

**Not yet style-driven (v1):** fonts are the system family (SF / SF Mono — no
custom font family); the quote bar color, code-block background tint, and
list-marker color use the engine's built-in defaults.

### Custom inline rules (hashtags, mentions, emoji)

Beyond standard Markdown, you can highlight and handle your own inline tokens —
`#hashtags`, `@mentions`, `:emoji:` shortcodes, anything with a trigger
character. Rules are a declarative, per-`MarkdownView` list; the CommonMark
parser is untouched, so this never changes how normal Markdown is parsed.

```swift
import Marked

let rules: [InlineRule] = [
    // #hashtag → blue, tappable
    InlineRule(
        id: "hashtag",
        trigger: "#",
        output: .styledText(InlineDecoration(
            color: CGColor(srgbRed: 0.15, green: 0.45, blue: 0.9, alpha: 1)
        ))
    ),
    // @mention → bold with a rounded "pill" background, tappable
    InlineRule(
        id: "mention",
        trigger: "@",
        output: .styledText(InlineDecoration(
            isBold: true,
            background: CGColor(srgbRed: 0.9, green: 0.94, blue: 1, alpha: 1)
        ))
    ),
    // :smile: → inline image, delimiters dropped, not tappable
    InlineRule(
        id: "emoji",
        trigger: ":",
        closing: ":",
        output: .image(keyPrefix: "emoji:"),   // ImageProvider key = "emoji:" + body
        isTappable: false
    ),
]

MarkdownView(
    "Hey @alice, ship #swift :rocket:",
    images: myEmojiProvider,        // resolves "emoji:rocket" for the :rocket: rule
    rules: rules,
    onCustomTap: { tap in
        // tap.ruleID == "hashtag" / "mention"; tap.value == "swift" / "alice"
        print(tap.ruleID, tap.value)
    }
)
```

**`InlineRule` fields:** `id` (returned on tap), `trigger` (the opening
character), `body` (allowed body characters — `.word` = letters/digits/`_`, or
`.custom(Set<Character>)`), `closing` (optional closing delimiter, e.g. `:` for
`:emoji:`), `minBodyLength` (default 1), `requiresLeadingBoundary` (default
`true` — so `email@host` does **not** match an `@` rule), `output`, and
`isTappable` (default `true`).

**`output`** is either `.styledText(InlineDecoration)` — with `color`, `isBold`,
`isItalic`, a rounded `background` pill, and `includeTrigger` (keep the `#`/`@`
in the displayed text, default `true`) — or `.image(keyPrefix:)`, which renders
an inline image whose `ImageProvider` key is `keyPrefix + body`.

Rules match inside emphasis (inheriting its italic/bold) but are **suppressed
inside real Markdown link labels and code spans**. When multiple rules share a
trigger, the first matching rule in the array wins. Tappable spans reuse the
same hit-testing as links; the pill background is drawn beneath text selection
and press highlights.

**Documented v1 limitations:** the leading-boundary check only sees the current
text node, so a token immediately following inline markup (e.g. `*a*@user`) can
still match; there is no `\#` escape to opt a token out.

### Display it (text engine)

The engine is Markdown-agnostic: it renders a generic `TextDocument`.

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

### Custom inline rules (`Marked`)

Per-`MarkdownView` declarative rules for custom inline tokens (hashtags,
mentions, emoji shortcodes) that render as styled text, a rounded "pill", or an
inline image, and dispatch a `CustomInlineTap` when tapped — layered on top of
the mapping stage without touching the CommonMark parser. See
[Custom inline rules](#custom-inline-rules-hashtags-mentions-emoji) above.

### Roadmap

The library is three specs, built in dependency order, plus a follow-on feature:

1. **Parser → AST** (`MarkdownAST`) — ✅ done.
2. **Text engine** (`MarkdownTextEngine`) — ✅ done.
3. **Markdown renderer** (`Marked`) — ✅ done.
4. **Custom inline rules** (`Marked`) — ✅ done.

## Development

```sh
swift build      # build
swift test       # run the test suite (558 tests)
swiftlint        # lint (config in .swiftlint.yml)
```

CI (GitHub Actions) on every push and pull request: full build + test on macOS
(the engine needs Apple frameworks), a Linux build guard for the
zero-dependency `MarkdownAST` target, and SwiftLint.

## License

[MIT](LICENSE) — do whatever you want with it.
