# Spec 2 — Text Engine (read-only typesetter)

**Date:** 2026-06-23
**Status:** Approved (design), pending implementation plan
**Module:** `MarkdownTextEngine` (Swift + Apple graphics frameworks; no third-party deps)

## Context

The SwiftUI Markdown library is built in three independent specs, in dependency
order:

1. **Spec 1 — Parser → AST** (`MarkdownAST`). **DONE** (2026-06-23).
2. **Spec 2 — Text engine (this document).** A read-only typesetter: a generic,
   Markdown-agnostic rich-document model → unified line layout + drawing +
   document-wide selection / hit-testing. Built on CoreText + Core Graphics,
   hosted in a `UIView`/`NSView` via a SwiftUI representable.
3. **Spec 3 — Markdown renderer.** Maps `MarkdownAST` (+ a style configuration)
   into the engine's `TextDocument`, wires link handling (openURL), and supplies
   image loading.

**Decision that supersedes the earlier Spec-3 sketch:** the engine **draws
everything itself** (text, lists, quotes, tables, code blocks, images, rules) in
one unified layout, so a single selection is continuous across the whole
document. Spec 3 therefore does **not** use SwiftUI `Grid`/`AsyncImage` for the
body; it builds a `TextDocument` and the engine renders it. (Confirmed in
brainstorming 2026-06-23.)

**Driving requirements (all must-have):** document-wide continuous selection;
custom inline content in the flow (inline images, custom spans); precise
typography + hit-testing; correct display + link tapping.

**Zero-dependency rule:** that rule is about the *parser* (no third-party parser,
ever — see Spec 1). A text engine necessarily uses Apple's platform frameworks
(CoreText, Core Graphics, SwiftUI, UIKit/AppKit); those are the platform, not
dependencies. No third-party packages.

**Targets:** iOS 26+ and macOS (multiplatform). The pure core is
platform-agnostic Apple Swift; only the hosting view is `#if`-guarded.

## Scope

**In scope (read-only):** unified layout + drawing of paragraphs, headings,
ordered/unordered/nested lists, block quotes (nested), GFM-style tables, code
blocks, images (block + inline), thematic breaks; emphasis/strong/strikethrough/
links/inline-code styling (as resolved inline runs); document-wide selection,
hit-testing, copy (plain text), word selection; link tap callbacks; async image
loading via a host-provided provider; native selection affordances (loupe, drag
handles, edit menu).

**Out of scope:** text **editing** (no insertion cursor, keyboard input, IME,
undo, model mutation); layout virtualization (full layout once + windowed draw —
suitable for articles/READMEs/chat/docs, not whole books); Markdown knowledge
(the engine is generic); style *selection* (the caller supplies resolved
styles); horizontal code scrolling (v1 wraps long code lines); rich-text /
Markdown copy formats (v1 copies plain text).

## Section 1 — Module boundary & architecture

Three layers, mirroring the parser's "pure testable core + thin wrapper +
platform shell" structure:

```
MarkdownTextEngine (target)
  PURE CORE (CoreText/Core Graphics geometry; no UIKit/SwiftUI; no Markdown)
    • TextDocument      value-type input model
    • LayoutEngine      TextDocument + width → DocumentLayout (pure geometry)
    • Selection         TextPosition/TextRange, hit-test, selection rects, copy
    • DocumentRenderer  DocumentLayout + CGContext + selection → drawing (thin)
  PLATFORM SHELL (#if canImport(UIKit) / canImport(AppKit))
    • TextEngineView    UIView/NSView: draw(rect:), gestures, edit menu, scroll
    • MarkdownTextView  UIViewRepresentable/NSViewRepresentable + config
    • ImageProvider     host-supplied async image loading (engine draws)
```

**Testability principle:** all logic — layout (block/line/cell geometry),
hit-testing, and selection (point↔position, selection rects, copy text) — is
**pure and TDD-testable** (assert `CGRect`s / positions / strings, no drawing).
Drawing is a thin mechanical layer (snapshot tests). Gestures/view are the
platform shell (manual / UI tests). ~80% of the logic is plain Swift Testing
TDD, like the parser.

**Boundaries:** the core knows nothing of SwiftUI/UIKit or of Markdown.
The shell holds no layout logic. `ImageProvider` isolates networking/loading
from the engine.

## Section 2 — Input model (`TextDocument`)

Generic and Markdown-agnostic. Spec 3 builds it from `MarkdownAST`; **styles
(fonts, colors, spacing) are already resolved by the caller** — the engine
applies them, never chooses them. Value types, `Equatable` (for TDD).

```swift
public struct TextDocument: Equatable {
    public var blocks: [Block]
}

public enum Block: Equatable {            // generic layout primitives
    case paragraph(Paragraph)             // a heading is a paragraph with a heading style
    case list(List)                       // ordered/unordered; items: [TextDocument] (recursive)
    case quote(TextDocument)              // nested document + left bar
    case table(Table)                     // rows × cells; per-column alignment; each cell = [InlineRun]
    case codeBlock(CodeBlock)             // preformatted lines + optional language label
    case image(ImageAttachment)           // source id + intrinsic size + alt
    case thematicBreak(RuleStyle)
}

public struct Paragraph: Equatable {
    public var runs: [InlineRun]
    public var style: ParagraphStyle      // indent, line spacing, alignment, spacing before/after
}

public indirect enum InlineRun: Equatable {
    case text(String, TextStyle)          // font, color, underline/strike, baseline offset
    case link(runs: [InlineRun], payload: LinkPayload)  // opaque payload → host resolves the tap
    case inlineImage(ImageAttachment)     // image in the text flow
    case lineBreak(hard: Bool)            // soft/hard break
}
```

`LinkPayload` is **opaque** (a host-defined token / URL string): the engine
returns it on tap and stays Markdown-agnostic. Lists and quotes nest via
recursive `TextDocument`. Tables/code/images are structured primitives.
`ParagraphStyle`/`TextStyle`/`CodeBlock`/`Table`/`List`/`ImageAttachment`/
`RuleStyle` carry resolved metrics (fonts, colors, paddings, alignments,
intrinsic sizes).

## Section 3 — `LayoutEngine` (pure geometry)

**Input:** `TextDocument` + available width (+ environment: writing direction,
default leading). **Output:** `DocumentLayout` — a tree of positioned frames plus
total content size.

Process — vertical block stacking (running Y cursor + spacing; width = available
− indent):

- **paragraph:** runs → CoreText line-breaking (`CTTypesetter`) → one `CTLine`
  per visual line; each `LineFrame` records origin, ascent/descent, width, the
  `CTLine`, and its **source character range** (for selection). Inline
  images/attachments use CoreText **run delegates** (reserve width/ascent/descent
  in the flow).
- **list:** marker (bullet/number) + recursive layout of each item's
  sub-`TextDocument` at an indent; record marker and item frames.
- **quote:** recursive layout of the inner document at an indent + the left-bar
  rect.
- **table:** measure intrinsic column widths → distribute to available width;
  lay out each cell's runs within its column width; row height = max cell height
  → a grid of cell frames + border geometry.
- **codeBlock:** preformatted (monospace) lines; long lines **wrap** in v1
  (horizontal scroll is v2) + background-box rect + optional language label.
- **image:** reserve intrinsic size (fit to width); placeholder until loaded.
- **thematicBreak:** a thin rule rect.

`DocumentLayout` exposes total content size, all block/line/cell frames, and a
flattened global index space (for selection). Re-layout on width change.

**Testability:** `TextDocument` + width → assert geometry (line count, wrap
points, line `origin.y`, table column widths, item indent). Deterministic with a
fixed test font.

## Section 4 — Selection & hit-testing (pure, testable)

- **`TextPosition`** — a document-wide position: a global character index over
  the flattened text (the engine numbers addressable characters by walking
  blocks/runs in order), resolvable to geometry via the layout. Total order →
  ranges work across blocks.
- **Hit-test:** point → nearest `TextPosition` (block by Y → line →
  `CTLineGetStringIndexForPosition`).
- **`TextRange`** = (start, end). **`SelectionGeometry`:** range + layout →
  `[CGRect]` highlight rects (partial first/last lines, full middle lines, across
  blocks/cells).
- **Copy:** range → plain string (walk the flattened text). Double-tap →
  expand to word boundaries (tokenization). Later: attributed/Markdown copy.
- **Non-text blocks** in a selection: an image/rule selects **atomically** (its
  rect highlighted; copy yields alt text / nothing); a table selection spans its
  cells. This is the payoff of "engine draws everything → uniform selection".

**Error handling:** layout is **total** — any `TextDocument` lays out (missing
image → placeholder; degenerate width → minimum). No `throws` (matches the
parser).

## Section 5 — `DocumentRenderer` (drawing, thin layer)

**Input:** `DocumentLayout` + `CGContext` + visible rect + selection state.
**Windowed:** draw only blocks intersecting the visible rect. Stateless — a pure
function of layout + context + selection.

Draw order: selection highlight (under text) → `CTLine`s (`CTLineDraw` at line
origins) → list markers → quote bars → table (borders + cell backgrounds + cell
text) → code box (rounded background + monospace lines + language label) → images
(loaded `CGImage` in the reserved frame / placeholder) → rules → pressed-link
highlight. Mechanical → snapshot tests (render to a buffer, compare to a
reference).

## Section 6 — Platform view + SwiftUI API + ImageProvider

**`TextEngineView` (UIView/NSView):** holds the `TextDocument`, the current
`DocumentLayout` (recomputed on bounds-width change), and selection state.
`draw(rect:)` → `DocumentRenderer` over the dirty rect (windowed). Gestures:
long-press → start selection + loupe; drag → extend + handles; double-tap →
word; tap → link hit-test → callback. Edit menu (`UIEditMenuInteraction` /
`NSMenu`): Copy / Look Up / Share. `intrinsicContentSize` = content size → lives
inside a SwiftUI `ScrollView`; width from the SwiftUI layout drives re-layout.
An async image finishing load invalidates its frame → partial redraw.

**`MarkdownTextView` — the public entry for Spec 3:**

```swift
public struct MarkdownTextView: View {        // UIViewRepresentable / NSViewRepresentable
    public init(_ document: TextDocument,
                isSelectable: Bool = true,
                onLink: ((LinkPayload) -> Void)? = nil,   // payload → host (openURL, …)
                images: ImageProvider? = nil,
                editMenu: EditMenuConfig = .standard)
}

public protocol ImageProvider: Sendable {     // loading = host, drawing = engine
    func image(for source: String) async -> CGImage?
}
```

Spec 3 builds the `TextDocument` from `MarkdownAST` + a style config, passes
`onLink` (openURL) and `images`. Platform code sits behind
`#if canImport(UIKit)`/`canImport(AppKit)`; the pure core contains none of it.

## Section 7 — Testing strategy

- **Pure core** (layout / selection / hit-test / copy): **TDD on Swift Testing**
  — assert geometry / positions / text against a deterministic test font. ~80%
  of the logic.
- **Drawing:** snapshot tests (render a layout → `CGImage` → compare to committed
  reference images).
- **View / gestures:** manual + a few UI tests.

One target `MarkdownTextEngine`: core + renderer (Core Graphics, cross-Apple),
with the platform view behind `#if`. CoreText/Core Graphics/SwiftUI/UIKit/AppKit
are platform frameworks (zero third-party deps preserved).

## Section 8 — Implementation waves

The spec defines the whole engine; the plan decomposes each wave into TDD
micro-tasks (writing-plans skill). Each wave ends as a working, tested
increment.

- **Wave 0 — Foundation.** Scaffold the `MarkdownTextEngine` target; the
  `TextDocument` model (value types, `Equatable`); a deterministic test-font
  helper. Green build + model tests.
- **Wave 1 — Paragraph layout.** `LayoutEngine` for paragraph/heading:
  CoreText line-breaking, `LineFrame` geometry, content size, width re-layout.
  (TDD geometry.)
- **Wave 2 — Selection core.** `TextPosition`/`TextRange`, flattened index
  space, hit-test (point→position), selection rects, copy text — for text
  blocks. (TDD.)
- **Wave 3 — Drawing + view (first end-to-end).** `DocumentRenderer`
  (paragraphs + selection), `TextEngineView` (UIView/NSView), `MarkdownTextView`
  representable, scroll, link tap. (Snapshot + manual.) First visible result.
- **Wave 4 — Lists & quotes.** Recursive sub-document layout, markers,
  indentation, quote bars (layout + draw + selection through them).
- **Wave 5 — Tables & code blocks.** Table grid layout (column widths, row
  heights, cell text), code-box layout/draw, language label; selection through
  cells.
- **Wave 6 — Images.** `ImageProvider`, image-attachment block + inline images,
  async load → redraw, placeholder/intrinsic sizing.
- **Wave 7 — Native selection UX.** Loupe, drag handles, double-tap word, edit
  menu (Copy / Look Up / Share), pressed-link highlight.
- **Wave 8 — Edge cases & gate.** Thematic breaks, empty document, degenerate
  width, large-document windowed-draw performance pass; final gate
  (build/test/lint/docs).

## Open questions / deferred decisions

- **RTL / bidi:** v1 targets LTR; bidirectional layout is a documented later
  concern (CoreText supports it; the model carries a writing-direction hint).
- **Horizontal code scrolling:** v1 wraps long code lines; horizontal scroll is
  deferred.
- **Rich copy:** v1 copies plain text; attributed/Markdown copy is deferred.
- **Layout virtualization:** deferred (full layout + windowed draw in v1).
