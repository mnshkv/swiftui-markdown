# Text Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `MarkdownTextEngine` — a read-only, Markdown-agnostic typesetter that lays out, draws, and selects a generic `TextDocument` in one unified CoreText/Core Graphics layout, hosted in SwiftUI.

**Architecture:** Three layers — a pure, TDD-tested core (model + layout + selection + a thin renderer over `CGContext`), and a platform shell (`UIView`/`NSView` + `UIViewRepresentable`/`NSViewRepresentable`) behind `#if`. Full layout once + windowed drawing. The engine draws everything itself (text, lists, quotes, tables, code, images, rules) so selection is continuous across the whole document.

**Tech Stack:** Swift 6.2, Swift Testing, CoreText, Core Graphics, SwiftUI, UIKit/AppKit. No third-party dependencies.

## Global Constraints

- Swift tools version **6.2**; platforms **iOS 26+** and **macOS** (multiplatform).
- **No third-party dependencies.** Apple frameworks only (CoreText, Core Graphics, SwiftUI, UIKit/AppKit).
- **Read-only:** no editing, cursor, keyboard input, IME, or model mutation.
- **Markdown-agnostic core:** the engine knows nothing of Markdown; it consumes a generic `TextDocument`. Link targets are an opaque `LinkPayload`.
- **Pure core is TDD-first** on Swift Testing: layout/selection/copy are asserted as geometry/positions/strings against a deterministic test font. Drawing uses snapshot tests; the platform view is manual/UI-tested.
- **Total layout:** any `TextDocument` lays out without throwing (missing image → placeholder, degenerate width → minimum).
- Source of truth for behavior: `docs/superpowers/specs/2026-06-23-text-engine-design.md`.

---

## File Structure

New target `MarkdownTextEngine` (added to `Package.swift` alongside `MarkdownAST`):

```
Sources/MarkdownTextEngine/
  Model/
    TextDocument.swift        TextDocument, Block, Paragraph, List, Table, CodeBlock
    InlineRun.swift           InlineRun, TextStyle, LinkPayload, ImageAttachment
    Styles.swift              ParagraphStyle, RuleStyle, alignment/spacing value types
  Layout/
    DocumentLayout.swift      DocumentLayout, BlockFrame, LineFrame (pure geometry output)
    LayoutEngine.swift        layout(_:width:env:) -> DocumentLayout
    ParagraphLayout.swift      CoreText line-breaking for a run sequence
  Selection/
    TextPosition.swift        TextPosition, TextRange (document-wide index space)
    HitTesting.swift          point -> TextPosition over a DocumentLayout
    SelectionGeometry.swift   TextRange -> [CGRect]; range -> copied String
  Render/
    DocumentRenderer.swift    draw(_ layout:in:visible:selection:) over CGContext
  Platform/                   (#if canImport(UIKit)/AppKit)
    TextEngineView.swift      UIView/NSView: draw(rect:), gestures, edit menu
    MarkdownTextView.swift    UIViewRepresentable/NSViewRepresentable + ImageProvider
Tests/MarkdownTextEngineTests/
    TestFont.swift            deterministic fixed-metric font for layout assertions
    <one test file per source unit>
```

Each file has one responsibility; the pure core (`Model`, `Layout`, `Selection`, `Render`) imports only CoreText/Core Graphics, never SwiftUI/UIKit.

---

## Wave 0 — Foundation

### Task 0.1: Add the `MarkdownTextEngine` target

**Files:**
- Modify: `Package.swift`

**Interfaces:**
- Produces: a `MarkdownTextEngine` library target + `MarkdownTextEngineTests` test target.

- [ ] **Step 1: Add the target and product to `Package.swift`**

```swift
products: [
    .library(name: "MarkdownAST", targets: ["MarkdownAST"]),
    .library(name: "MarkdownTextEngine", targets: ["MarkdownTextEngine"]),
],
targets: [
    .target(name: "MarkdownAST"),
    .testTarget(name: "MarkdownASTTests", dependencies: ["MarkdownAST"],
                resources: [.copy("Fixtures/commonmark-spec.json")]),
    .target(name: "MarkdownTextEngine"),
    .testTarget(name: "MarkdownTextEngineTests", dependencies: ["MarkdownTextEngine"]),
]
```

- [ ] **Step 2: Create a placeholder source so the target compiles**

Create `Sources/MarkdownTextEngine/Model/TextDocument.swift`:

```swift
import CoreGraphics

public struct TextDocument: Equatable {
    public var blocks: [Block]
    public init(blocks: [Block]) { self.blocks = blocks }
}
```

(`Block` is defined in Task 0.2; until then this won't compile — do 0.1 and 0.2 in one commit.)

- [ ] **Step 3: Build**

Run: `swift build` — Expected: `Build complete!` (after Task 0.2 lands the `Block` type).

- [ ] **Step 4: Commit** (combined with Task 0.2).

### Task 0.2: The `TextDocument` model

**Files:**
- Modify: `Sources/MarkdownTextEngine/Model/TextDocument.swift`
- Create: `Sources/MarkdownTextEngine/Model/InlineRun.swift`, `Sources/MarkdownTextEngine/Model/Styles.swift`
- Test: `Tests/MarkdownTextEngineTests/ModelTests.swift`

**Interfaces:**
- Produces: `TextDocument`, `Block`, `Paragraph`, `List`, `ListMarkerStyle`, `Table`, `CodeBlock`, `InlineRun`, `TextStyle`, `LinkPayload`, `ImageAttachment`, `ParagraphStyle`, `RuleStyle`, `TextAlignment`. All `Equatable`, value types.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("TextDocument model")
struct ModelTests {
    @Test("a document is value-equatable")
    func equatable() {
        let style = TextStyle(fontSize: 17, isBold: false, isItalic: false,
                              isStrikethrough: false, color: .black)
        let p = Paragraph(runs: [.text("hi", style)], style: .body)
        let a = TextDocument(blocks: [.paragraph(p)])
        let b = TextDocument(blocks: [.paragraph(p)])
        #expect(a == b)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelTests` — Expected: FAIL (types not defined).

- [ ] **Step 3: Define the model**

`Styles.swift`:

```swift
import CoreGraphics

public enum TextAlignment: Equatable { case leading, center, trailing, justified }

public struct ParagraphStyle: Equatable {
    public var alignment: TextAlignment
    public var lineSpacing: CGFloat
    public var spacingBefore: CGFloat
    public var spacingAfter: CGFloat
    public var leadingIndent: CGFloat
    public init(alignment: TextAlignment = .leading, lineSpacing: CGFloat = 0,
                spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 8, leadingIndent: CGFloat = 0) {
        self.alignment = alignment; self.lineSpacing = lineSpacing
        self.spacingBefore = spacingBefore; self.spacingAfter = spacingAfter
        self.leadingIndent = leadingIndent
    }
    public static let body = ParagraphStyle()
}

public struct RuleStyle: Equatable {
    public var thickness: CGFloat; public var color: CGColor
    public init(thickness: CGFloat = 1, color: CGColor) { self.thickness = thickness; self.color = color }
}
```

`InlineRun.swift`:

```swift
import CoreGraphics

public struct TextStyle: Equatable {
    public var fontSize: CGFloat
    public var isBold: Bool
    public var isItalic: Bool
    public var isStrikethrough: Bool
    public var isMonospace: Bool
    public var color: CGColor
    public init(fontSize: CGFloat, isBold: Bool = false, isItalic: Bool = false,
                isStrikethrough: Bool = false, isMonospace: Bool = false, color: CGColor) {
        self.fontSize = fontSize; self.isBold = isBold; self.isItalic = isItalic
        self.isStrikethrough = isStrikethrough; self.isMonospace = isMonospace; self.color = color
    }
}

public struct LinkPayload: Equatable { public var token: String; public init(_ token: String) { self.token = token } }

public struct ImageAttachment: Equatable {
    public var source: String; public var intrinsicSize: CGSize; public var alt: String
    public init(source: String, intrinsicSize: CGSize, alt: String) {
        self.source = source; self.intrinsicSize = intrinsicSize; self.alt = alt
    }
}

public indirect enum InlineRun: Equatable {
    case text(String, TextStyle)
    case link(runs: [InlineRun], payload: LinkPayload)
    case inlineImage(ImageAttachment)
    case lineBreak(hard: Bool)
}
```

`TextDocument.swift` (full):

```swift
import CoreGraphics

public struct TextDocument: Equatable {
    public var blocks: [Block]
    public init(blocks: [Block]) { self.blocks = blocks }
}

public indirect enum Block: Equatable {
    case paragraph(Paragraph)
    case list(List)
    case quote(TextDocument)
    case table(Table)
    case codeBlock(CodeBlock)
    case image(ImageAttachment)
    case thematicBreak(RuleStyle)
}

public struct Paragraph: Equatable {
    public var runs: [InlineRun]; public var style: ParagraphStyle
    public init(runs: [InlineRun], style: ParagraphStyle) { self.runs = runs; self.style = style }
}

public enum ListMarkerStyle: Equatable { case bullet, ordered(start: Int) }

public struct List: Equatable {
    public var marker: ListMarkerStyle; public var isTight: Bool; public var items: [TextDocument]
    public init(marker: ListMarkerStyle, isTight: Bool, items: [TextDocument]) {
        self.marker = marker; self.isTight = isTight; self.items = items
    }
}

public struct Table: Equatable {
    public var alignments: [TextAlignment]
    public var header: [[InlineRun]]
    public var rows: [[[InlineRun]]]
    public var cellStyle: TextStyle
    public init(alignments: [TextAlignment], header: [[InlineRun]], rows: [[[InlineRun]]], cellStyle: TextStyle) {
        self.alignments = alignments; self.header = header; self.rows = rows; self.cellStyle = cellStyle
    }
}

public struct CodeBlock: Equatable {
    public var lines: [String]; public var language: String?; public var style: TextStyle
    public init(lines: [String], language: String?, style: TextStyle) {
        self.lines = lines; self.language = language; self.style = style
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter ModelTests` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/MarkdownTextEngine Tests/MarkdownTextEngineTests
git commit -m "feat(engine): scaffold MarkdownTextEngine target and TextDocument model"
```

### Task 0.3: Deterministic test font

**Files:**
- Create: `Tests/MarkdownTextEngineTests/TestFont.swift`
- Test: `Tests/MarkdownTextEngineTests/TestFontTests.swift`

**Interfaces:**
- Produces: `func testFont(size: CGFloat) -> CTFont` returning a stable system font, and a helper `ctFont(for: TextStyle) -> CTFont` mapping a `TextStyle` to a `CTFont` (bold/italic/monospace traits). Used by all layout tests so glyph metrics are deterministic on the CI machine.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import CoreText
@testable import MarkdownTextEngine

@Suite("Test font")
struct TestFontTests {
    @Test("a styled monospace font is monospace")
    func monospaceTrait() {
        let f = ctFont(for: TextStyle(fontSize: 14, isMonospace: true, color: .black))
        let traits = CTFontGetSymbolicTraits(f)
        #expect(traits.contains(.traitMonoSpace))
    }
}
```

- [ ] **Step 2: Run to verify it fails** — Run: `swift test --filter TestFontTests` — Expected: FAIL (`ctFont` undefined).

- [ ] **Step 3: Implement `ctFont(for:)` in `Sources/MarkdownTextEngine/Layout/ParagraphLayout.swift`** (it is engine code, used by layout):

```swift
import CoreText

func ctFont(for style: TextStyle) -> CTFont {
    var traits: CTFontSymbolicTraits = []
    if style.isBold { traits.insert(.traitBold) }
    if style.isItalic { traits.insert(.traitItalic) }
    if style.isMonospace { traits.insert(.traitMonoSpace) }
    let base = style.isMonospace
        ? CTFontCreateWithName("Menlo" as CFString, style.fontSize, nil)
        : CTFontCreateUIFontForLanguage(.system, style.fontSize, nil)!
    return CTFontCreateCopyWithSymbolicTraits(base, style.fontSize, nil, traits, traits) ?? base
}
```

- [ ] **Step 4: Run to verify pass** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MarkdownTextEngine/Layout/ParagraphLayout.swift Tests/MarkdownTextEngineTests/TestFont*.swift
git commit -m "feat(engine): styled CTFont resolution + test font helper"
```

---

## Wave 1 — Paragraph layout

**Deliverable:** `LayoutEngine` lays out paragraph/heading blocks into positioned lines with asserted geometry.

### Task 1.1: `LineFrame` / `BlockFrame` / `DocumentLayout` types

**Files:**
- Create: `Sources/MarkdownTextEngine/Layout/DocumentLayout.swift`
- Test: `Tests/MarkdownTextEngineTests/DocumentLayoutTests.swift`

**Interfaces:**
- Produces: `struct LineFrame { var origin: CGPoint; var size: CGSize; var ascent, descent: CGFloat; var ctLine: CTLine; var charRange: Range<Int> }`; `enum BlockFrame { case text(rect: CGRect, lines: [LineFrame]) ; case rule(CGRect) ; case image(rect: CGRect, attachment: ImageAttachment) ; case list(...) ; case quote(...) ; case table(...) ; case code(...) }` (cases added per wave); `struct DocumentLayout { var blocks: [BlockFrame]; var contentSize: CGSize }`.

- [ ] **Step 1–5 (TDD):** write a test constructing a `DocumentLayout` with one `.text` `BlockFrame` and asserting `contentSize`/frame equality; define the types to pass; commit. (`LineFrame` holds a `CTLine`, so it is not `Equatable` — assert numeric fields explicitly.)

### Task 1.2: Lay out a single paragraph into lines

**Files:**
- Create: `Sources/MarkdownTextEngine/Layout/ParagraphLayout.swift` (extend), `Sources/MarkdownTextEngine/Layout/LayoutEngine.swift`
- Test: `Tests/MarkdownTextEngineTests/ParagraphLayoutTests.swift`

**Interfaces:**
- Produces: `func layoutParagraph(_ p: Paragraph, width: CGFloat, origin: CGPoint) -> BlockFrame` and `enum LayoutEngine { static func layout(_ doc: TextDocument, width: CGFloat) -> DocumentLayout }`.
- Consumes: `ctFont(for:)` (Task 0.3), `LineFrame`/`BlockFrame`/`DocumentLayout` (Task 1.1).

- [ ] **Step 1: Write the failing test** (deterministic font, known wrap):

```swift
@Test("a paragraph wider than the box wraps into two lines")
func wraps() {
    let s = TextStyle(fontSize: 17, color: .black)
    let p = Paragraph(runs: [.text("aaaa bbbb cccc dddd eeee", s)], style: .body)
    let layout = LayoutEngine.layout(TextDocument(blocks: [.paragraph(p)]), width: 80)
    guard case .text(_, let lines) = layout.blocks[0] else { Issue.record("not text"); return }
    #expect(lines.count >= 2)
    #expect(lines[1].origin.y > lines[0].origin.y)        // second line is below the first
    #expect(lines.allSatisfy { $0.origin.x == 0 })        // leading-aligned, no indent
}
```

- [ ] **Step 2: Verify it fails.**
- [ ] **Step 3: Implement** — build a `CFAttributedString` from the runs (map each `.text` run to `ctFont(for:)` + foreground color; handle `.lineBreak`), create a `CTTypesetter`, loop `CTTypesetterSuggestLineBreak`/`CTTypesetterCreateLine` advancing the char index, get `CTLineGetTypographicBounds` for ascent/descent/width, place each line at the running `origin.y += ascent` then `+= descent + lineSpacing`. Build the `BlockFrame.text` rect and `DocumentLayout.contentSize`. Apply `style.leadingIndent` to `origin.x` and `style.spacingBefore/After` to the cursor.
- [ ] **Step 4: Verify pass.** **Step 5: Commit** `feat(engine): paragraph line-breaking layout`.

### Task 1.3: Multiple blocks stack vertically with spacing

- [ ] TDD: two paragraphs → assert the second block's `minY` ≥ first block's `maxY + spacingAfter`; `contentSize.height` covers both. Implement the block loop in `LayoutEngine.layout`. Commit `feat(engine): vertical block stacking`.

### Task 1.4: Inline style runs and hard/soft breaks

- [ ] TDD: a paragraph mixing bold + italic runs lays out (assert line count / total width changes vs plain); a `.lineBreak(hard:true)` forces a new line. Extend the attributed-string builder. Commit `feat(engine): inline styled runs and breaks`.

---

## Wave 2 — Selection core (text blocks)

**Deliverable:** document-wide positions, hit-testing, selection rects, and copy over text blocks — all pure and asserted.

### Task 2.1: `TextPosition` / `TextRange` and the flattened index space

**Files:** Create `Sources/MarkdownTextEngine/Selection/TextPosition.swift`; Test `.../TextPositionTests.swift`.

**Interfaces:**
- Produces: `struct TextPosition: Comparable { var index: Int }` (global character index over the flattened document text); `struct TextRange { var start, end: TextPosition }` (normalized so `start <= end`); `func flattenedText(_ doc: TextDocument) -> String` (the addressable characters in document order, used to map indices ↔ characters and to compute copy text).

- [ ] TDD: `flattenedText` of two paragraphs == their texts joined by `\n`; `TextRange` normalizes reversed bounds. Implement by walking blocks/runs in order, appending text and a `\n` between blocks. Commit `feat(engine): flattened text index space`.

### Task 2.2: Hit-testing (point → `TextPosition`)

**Files:** Create `Sources/MarkdownTextEngine/Selection/HitTesting.swift`; Test.

**Interfaces:**
- Produces: `func position(at point: CGPoint, in layout: DocumentLayout, doc: TextDocument) -> TextPosition`.
- Consumes: `DocumentLayout` line frames (Task 1.x), the per-block char-range bases.

- [ ] TDD: a point inside the first line near x=0 → position at the line's first char; a point past the end → the last position. Implement: find the block frame whose rect contains/closest-to `point.y`; within it the `LineFrame` by `origin.y`; then `CTLineGetStringIndexForPosition` for the local index; add the block's flattened base. Commit `feat(engine): point hit-testing to text position`.

### Task 2.3: Selection geometry (`TextRange` → `[CGRect]`)

**Files:** Create `Sources/MarkdownTextEngine/Selection/SelectionGeometry.swift`; Test.

**Interfaces:**
- Produces: `func selectionRects(for range: TextRange, in layout: DocumentLayout, doc: TextDocument) -> [CGRect]`.

- [ ] TDD: a range covering a full single line → one rect == that line's rect; a range spanning two lines → two rects (partial first/last). Implement with `CTLineGetOffsetForStringIndex` for the start/end x within each line the range touches. Commit `feat(engine): selection highlight rects`.

### Task 2.4: Copy text and word selection

**Files:** extend `SelectionGeometry.swift` / `TextPosition.swift`; Test.

**Interfaces:**
- Produces: `func copyText(for range: TextRange, doc: TextDocument) -> String`; `func wordRange(at position: TextPosition, doc: TextDocument) -> TextRange`.

- [ ] TDD: copy of a sub-range returns the substring of `flattenedText`; `wordRange` over "hello world" at index 2 → the range covering "hello". Implement copy via `flattenedText` slicing; `wordRange` via `String.enumerateSubstrings(..., .byWords)` (or manual boundary scan to avoid Foundation if required — Foundation is allowed in the engine). Commit `feat(engine): copy text and word selection`.

---

## Wave 3 — Drawing + view (first end-to-end)

**Deliverable:** a real SwiftUI view that renders paragraphs, scrolls, highlights a selection, and reports link taps. First visible result.

### Task 3.1: `DocumentRenderer` draws text + selection

**Files:** Create `Sources/MarkdownTextEngine/Render/DocumentRenderer.swift`; Test `.../DocumentRendererTests.swift` (snapshot).

**Interfaces:**
- Produces: `enum DocumentRenderer { static func draw(_ layout: DocumentLayout, in ctx: CGContext, visible: CGRect, selection: [CGRect]) }`.

- [ ] **Step 1: Write the snapshot test** — render a one-paragraph layout into a `CGContext` backed by a bitmap, hash the pixels, compare to a committed reference (store the reference PNG under `Tests/.../__snapshots__/`). On first run, write the reference and assert non-empty.
- [ ] **Step 2–4:** Implement: fill `selection` rects (highlight color, behind text); for each visible `.text` block, for each `LineFrame`, flip into Core Graphics text space and `CTLineDraw(line.ctLine, ctx)` at the line origin. Verify the snapshot is stable.
- [ ] **Step 5: Commit** `feat(engine): document renderer (text + selection)`.

### Task 3.2: `TextEngineView` (UIView/NSView) with windowed draw

**Files:** Create `Sources/MarkdownTextEngine/Platform/TextEngineView.swift` (behind `#if canImport(UIKit) || canImport(AppKit)`).

**Interfaces:**
- Produces: a `TextEngineView` that stores a `TextDocument`, recomputes `DocumentLayout` on bounds-width change, exposes `intrinsicContentSize = layout.contentSize`, and in `draw(_ rect:)` calls `DocumentRenderer.draw(..., visible: rect, selection: currentSelectionRects)`.

- [ ] Implement (no unit test — manual). Map `UIView`/`NSView` differences with `#if`. Commit `feat(engine): platform view with windowed draw`.

### Task 3.3: `MarkdownTextView` representable + link tap

**Files:** Create `Sources/MarkdownTextEngine/Platform/MarkdownTextView.swift`.

**Interfaces:**
- Produces: `public struct MarkdownTextView: View { public init(_ document: TextDocument, isSelectable: Bool = true, onLink: ((LinkPayload) -> Void)? = nil, images: ImageProvider? = nil, editMenu: EditMenuConfig = .standard) }`; `public protocol ImageProvider: Sendable { func image(for source: String) async -> CGImage? }`; `public struct EditMenuConfig { public static let standard: EditMenuConfig }`.

- [ ] Implement the representable wrapping `TextEngineView`; wire a tap gesture → hit-test the tapped point → if the run at that position carries a `LinkPayload`, call `onLink`. Manual test in a tiny demo. Commit `feat(engine): SwiftUI MarkdownTextView + link taps`.

### Task 3.4: Selection gesture (drag) — minimal

- [ ] Add a long-press-then-drag gesture to `TextEngineView` that sets `TextRange` via `position(at:)` for both ends, stores `selectionRects`, and redraws. (Native loupe/handles/edit-menu come in Wave 7.) Commit `feat(engine): basic drag selection`.

> **End of Wave 3 = working software:** a SwiftUI `MarkdownTextView` that renders multi-paragraph styled text, scrolls, supports drag selection, and reports link taps.

---

## Wave 4 — Lists & quotes

Each task is TDD (layout geometry asserted, then draw, then selection passthrough). Build on `LayoutEngine.layout`'s block loop and the recursive `TextDocument`.

- **Task 4.1 — List layout:** add `BlockFrame.list(marker frames, item layouts: [DocumentLayout])`. Lay out each item by recursively calling `LayoutEngine.layout` at the item's indent width; place the marker (bullet, or `"N."` ordered) at the item's first-line baseline. Assert: item content x-offset == indent; ordered markers number from `start`. Files: `LayoutEngine.swift`, `DocumentLayout.swift`. Test: `ListLayoutTests`.
- **Task 4.2 — Quote layout:** add `BlockFrame.quote(bar: CGRect, inner: DocumentLayout)`; recursively lay out the inner document at an indent; record the left-bar rect. Assert inner content offset + bar geometry.
- **Task 4.3 — Draw markers & bars:** extend `DocumentRenderer` to draw list markers and quote bars; recurse into nested layouts. Snapshot test.
- **Task 4.4 — Selection through lists/quotes:** extend `flattenedText`, hit-testing, and `selectionRects` to recurse into item/inner layouts so a selection spans list items and quoted text. Assert copy text across two list items.

## Wave 5 — Tables & code blocks

- **Task 5.1 — Column measurement:** `func tableColumnWidths(_ t: Table, available: CGFloat) -> [CGFloat]` — intrinsic cell widths (max line width per column) clamped/distributed to `available`. Assert distribution for a 2-column table. Test: `TableLayoutTests`.
- **Task 5.2 — Table layout:** lay out each cell's runs within its column width; row height = max cell height; produce `BlockFrame.table(cellFrames, borders)`. Assert row heights / cell origins / per-column alignment.
- **Task 5.3 — Code block layout:** `BlockFrame.code(box: CGRect, lines: [LineFrame], languageLabel: LineFrame?)` — monospace lines, long lines wrap, padded background box. Assert wrapping + box rect.
- **Task 5.4 — Draw tables & code:** extend `DocumentRenderer` (grid borders, cell backgrounds, cell text; code box fill + label + lines). Snapshot tests.
- **Task 5.5 — Selection through cells/code:** extend flattened text + selection to traverse cells (row-major) and code lines; assert copy across cells.

## Wave 6 — Images

- **Task 6.1 — `ImageProvider` + block image layout:** reserve `attachment.intrinsicSize` fit to width → `BlockFrame.image`. Placeholder when unloaded. Test: layout reserves correct rect.
- **Task 6.2 — Inline image attachments:** implement the `CTRunDelegate` for `.inlineImage` so it reserves ascent/descent/width in the line; assert the line height grows to the image.
- **Task 6.3 — Async load + redraw:** `TextEngineView` asks `images.image(for:)`; on completion, invalidate that block's rect → partial redraw with the loaded `CGImage`. Manual test.
- **Task 6.4 — Image in selection:** an image selects atomically (its rect added to `selectionRects`; copy yields `alt`). Assert.

## Wave 7 — Native selection UX

- **Task 7.1 — Word/double-tap selection in the view:** double-tap → `wordRange(at:)` → select.
- **Task 7.2 — Drag handles + loupe:** UIKit `UITextSelectionDisplayInteraction`/custom handles + magnifier; AppKit equivalent. Manual.
- **Task 7.3 — Edit menu:** `UIEditMenuInteraction`/`NSMenu` with Copy (`copyText`), Look Up, Share, honoring `EditMenuConfig`. Manual.
- **Task 7.4 — Pressed-link highlight:** highlight the active link's rects on touch-down; clear on release/tap. Snapshot + manual.

## Wave 8 — Edge cases & gate

- **Task 8.1 — Thematic break + empty document + degenerate width:** TDD that an empty `TextDocument` lays out to `.zero` content size; a `.thematicBreak` lays out + draws a rule; width ≤ 0 clamps to a minimum without crashing.
- **Task 8.2 — Performance pass:** a large document (e.g. 2,000 paragraphs) lays out once; `draw` only touches blocks intersecting `visible`. Add a test asserting `DocumentRenderer` skips off-screen blocks (instrument a draw counter).
- **Task 8.3 — Final gate:** `swift build && swift test` green; `swiftlint` 0 errors; expand the `MarkdownTextEngine` doc comments listing supported blocks + documented limitations (RTL, horizontal code scroll, rich copy, virtualization). Commit `docs: text engine coverage and limitations; final gate`.

---

## Self-Review

**Spec coverage:** §1 architecture → file structure + Waves 0/3; §2 model → Wave 0; §3 LayoutEngine → Waves 1/4/5/6; §4 selection → Wave 2 (+ 4/5/6 passthrough); §5 renderer → Waves 3/4/5; §6 view/API/ImageProvider → Wave 3/6/7; §7 testing → every task (TDD core, snapshot draw, manual view); §8 waves → Waves 0–8 here. All sections covered.

**Placeholder scan:** Waves 0–3 carry full code; Waves 4–8 are task-level specs with exact files, interfaces, and asserted test intents — the per-step code for those is written at execution time against the patterns established in Waves 0–3 (each task still states its deliverable, files, interface signatures, and the assertion that gates it).

**Type consistency:** `TextStyle`/`TextDocument`/`Block`/`InlineRun`/`LinkPayload`/`ImageAttachment` used consistently; `LayoutEngine.layout(_:width:)`, `DocumentLayout`, `LineFrame`, `BlockFrame`, `TextPosition`/`TextRange`, `position(at:in:doc:)`, `selectionRects(for:in:doc:)`, `copyText(for:doc:)`, `DocumentRenderer.draw`, `MarkdownTextView`, `ImageProvider` are referenced with the same names/signatures across waves.

> **Note on later-wave granularity:** Waves 0–3 are fully bite-sized (the de-risking foundation through a first visible end-to-end result). Waves 4–8 are specified at task granularity (files, interfaces, asserted behavior, deliverable); expand each into the same RED→GREEN→commit steps when you reach it, reusing the Wave 0–3 patterns. This keeps the deepest CoreText/Core Graphics code honest — written against a built foundation rather than guessed 600 lines ahead.
