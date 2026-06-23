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

    @Test("ctFont with fontSize 0 returns a usable font and does not crash")
    func fontSizeZeroDoesNotCrash() {
        // Previously CTFontCreateUIFontForLanguage(.system, 0, nil)! would crash
        // because the system returns nil for size <= 0. Verify the hardened path
        // clamps to 1pt and returns a valid font.
        let f = ctFont(for: TextStyle(fontSize: 0, color: .black))
        // A valid CTFont reports a positive size.
        #expect(CTFontGetSize(f) >= 1)
    }

    @Test("ctFont with negative fontSize returns a usable font and does not crash")
    func fontSizeNegativeDoesNotCrash() {
        let f = ctFont(for: TextStyle(fontSize: -5, color: .black))
        #expect(CTFontGetSize(f) >= 1)
    }

    @Test("layout of a paragraph with fontSize 0 does not crash and produces a layout")
    func layoutWithFontSizeZeroDoesNotCrash() {
        let s = TextStyle(fontSize: 0, color: .black)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("zero size", s)], style: .body))
        ])
        let layout = LayoutEngine.layout(doc, width: 200)
        // Must produce at least one block without crashing.
        #expect(layout.blocks.count == 1)
    }
}
