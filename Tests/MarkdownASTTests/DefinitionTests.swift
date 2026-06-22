import Testing
@testable import MarkdownAST

@Suite("Link reference & footnote definition collection (Pass A)")
struct DefinitionTests {

    // MARK: - Link reference definitions

    @Test("[id]: url \"T\" collected and removed from blocks")
    func linkDefCollectedAndRemovedFromBlocks() {
        let store = DefinitionStore()
        let out = BlockParser(defs: store).parse(["[id]: https://example.com \"T\""], depth: 0)
        #expect(out == [])
        #expect(store.link(for: "id")?.destination == "https://example.com")
        #expect(store.link(for: "id")?.title == "T")
    }

    @Test("angle-bracket destination with spaces")
    func angleBracketDestWithSpaces() {
        let store = DefinitionStore()
        let out = BlockParser(defs: store).parse(["[id]: <url with spaces> \"T\""], depth: 0)
        #expect(out == [])
        #expect(store.link(for: "id")?.destination == "url with spaces")
        #expect(store.link(for: "id")?.title == "T")
    }

    @Test("link reference definition with no title stores nil")
    func linkDefNoTitle() {
        let store = DefinitionStore()
        let out = BlockParser(defs: store).parse(["[id]: https://example.com"], depth: 0)
        #expect(out == [])
        #expect(store.link(for: "id")?.destination == "https://example.com")
        #expect(store.link(for: "id")?.title == nil)
    }

    @Test("link-ref-def does NOT interrupt paragraph (CommonMark §6.1 ex 213)")
    func linkDefDoesNotInterruptParagraph() {
        let store = DefinitionStore()
        let out = BlockParser(defs: store).parse(["para", "[id]: x"], depth: 0)
        #expect(out == [.paragraph(raw: "para\n[id]: x")])
        #expect(store.link(for: "id") == nil)
    }

    @Test("link-ref-def after a blank line is collected")
    func linkDefAfterBlankLine() {
        let store = DefinitionStore()
        let out = BlockParser(defs: store).parse(["para", "", "[id]: https://example.com"], depth: 0)
        #expect(out == [.paragraph(raw: "para")])
        #expect(store.link(for: "id")?.destination == "https://example.com")
    }

    @Test("trailing junk after title rejects the link-ref-def")
    func trailingJunkRejected() {
        let store = DefinitionStore()
        let out = BlockParser(defs: store).parse(["[id]: url \"title\" junk"], depth: 0)
        #expect(out == [.paragraph(raw: "[id]: url \"title\" junk")])
        #expect(store.link(for: "id") == nil)
    }

    @Test("empty title string is stored as empty, not nil")
    func linkDefEmptyTitle() {
        let store = DefinitionStore()
        let out = BlockParser(defs: store).parse(["[id]: https://example.com \"\""], depth: 0)
        #expect(out == [])
        #expect(store.link(for: "id")?.title == "")
    }

    @Test("single-quoted and parenthesized titles")
    func linkDefAlternateTitleDelimiters() {
        let store1 = DefinitionStore()
        _ = BlockParser(defs: store1).parse(["[id]: url 'T'"], depth: 0)
        #expect(store1.link(for: "id")?.title == "T")

        let store2 = DefinitionStore()
        _ = BlockParser(defs: store2).parse(["[id]: url (T)"], depth: 0)
        #expect(store2.link(for: "id")?.title == "T")
    }

    // MARK: - Footnote definitions

    @Test("[^1]: a note — single-line footnote collected")
    func footnoteSingleLine() {
        let store = DefinitionStore()
        let out = BlockParser(defs: store).parse(["[^1]: a note"], depth: 0)
        #expect(out == [])
        #expect(store.hasFootnote("1") == true)
        let pending = store.pendingFootnotes.first
        #expect(pending?.id == "1")
        #expect(pending?.bodyLines == ["a note"])
    }

    @Test("[^1]: a / blank / indented para2 — multi-paragraph body")
    func footnoteMultiParagraph() {
        let store = DefinitionStore()
        let out = BlockParser(defs: store).parse(["[^1]: a", "", "    para2"], depth: 0)
        #expect(out == [])
        #expect(store.hasFootnote("1") == true)
        let pending = store.pendingFootnotes.first
        #expect(pending?.id == "1")
        #expect(pending?.bodyLines == ["a", "", "para2"])
    }

    @Test("footnote body stops at dedented sibling")
    func footnoteBodyStopsAtDedent() {
        let store = DefinitionStore()
        let out = BlockParser(defs: store).parse(["[^1]: a", "", "dedented"], depth: 0)
        #expect(out == [.paragraph(raw: "dedented")])
        #expect(store.hasFootnote("1") == true)
        let pending = store.pendingFootnotes.first
        #expect(pending?.bodyLines == ["a"])
    }

    @Test("footnote def does NOT interrupt paragraph")
    func footnoteDefDoesNotInterruptParagraph() {
        let store = DefinitionStore()
        let out = BlockParser(defs: store).parse(["para", "[^1]: a"], depth: 0)
        #expect(out == [.paragraph(raw: "para\n[^1]: a")])
        #expect(store.hasFootnote("1") == false)
    }
}
