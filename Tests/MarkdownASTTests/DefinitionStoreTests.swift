import Testing
@testable import MarkdownAST

@Suite("DefinitionStore")
final class DefinitionStoreTests {

    // MARK: - normalize

    @Test("normalize trims, lowercases, and collapses internal whitespace")
    func normalizeBasic() {
        #expect(DefinitionStore.normalize("Foo  BAR") == "foo bar")
    }

    @Test("normalize handles tabs and surrounding whitespace")
    func normalizeTabsAndEdges() {
        #expect(DefinitionStore.normalize("  Foo\tBAR  ") == "foo bar")
    }

    @Test("normalize collapses newlines into a single space")
    func normalizeNewlines() {
        #expect(DefinitionStore.normalize("Foo\n\nBAR") == "foo bar")
    }

    @Test("normalize of empty string is empty")
    func normalizeEmpty() {
        #expect(DefinitionStore.normalize("") == "")
        #expect(DefinitionStore.normalize("   \t  ") == "")
    }

    // MARK: - addLink / link(for:)

    @Test("first definition wins for duplicate labels")
    func firstDefWins() {
        let store = DefinitionStore()
        store.addLink(label: "a", destination: "x", title: nil)
        store.addLink(label: "a", destination: "y", title: "second")
        let def = store.link(for: "a")
        #expect(def != nil)
        #expect(def?.destination == "x")
        #expect(def?.title == nil)
    }

    @Test("label lookup is case-insensitive via normalize")
    func lookupCaseInsensitive() {
        let store = DefinitionStore()
        store.addLink(label: "a", destination: "x", title: nil)
        #expect(store.link(for: "A")?.destination == "x")
        #expect(store.link(for: "  A  ")?.destination == "x")
    }

    @Test("unknown label returns nil")
    func unknownLink() {
        let store = DefinitionStore()
        #expect(store.link(for: "missing") == nil)
    }

    @Test("distinct labels coexist")
    func distinctLabels() {
        let store = DefinitionStore()
        store.addLink(label: "a", destination: "x", title: nil)
        store.addLink(label: "b", destination: "y", title: "t")
        #expect(store.link(for: "a")?.destination == "x")
        #expect(store.link(for: "b")?.destination == "y")
        #expect(store.link(for: "b")?.title == "t")
    }

    // MARK: - addFootnote / hasFootnote

    @Test("hasFootnote true after add, false for unknown")
    func hasFootnoteBasic() {
        let store = DefinitionStore()
        #expect(store.hasFootnote("1") == false)
        store.addFootnote(id: "1", bodyLines: ["note body"])
        #expect(store.hasFootnote("1") == true)
        #expect(store.hasFootnote("2") == false)
    }

    @Test("pendingFootnotes stores raw body lines retrievably")
    func pendingFootnotesRetainsBodyLines() {
        let store = DefinitionStore()
        store.addFootnote(id: "1", bodyLines: ["first line", "second line"])
        #expect(store.pendingFootnotes.count == 1)
        let pending = store.pendingFootnotes.first
        #expect(pending?.id == "1")
        #expect(pending?.bodyLines == ["first line", "second line"])
    }

    @Test("addFootnote preserves insertion order")
    func pendingFootnotesOrder() {
        let store = DefinitionStore()
        store.addFootnote(id: "alpha", bodyLines: ["a"])
        store.addFootnote(id: "beta", bodyLines: ["b"])
        #expect(store.pendingFootnotes.map(\.id) == ["alpha", "beta"])
    }
}
