import Testing
@testable import MarkdownAST

@Suite("Emphasis flanking classification")
struct FlankingTests {
    @Test("`*` opener is left-flanking, closer is right-flanking")
    func starFlanking() {
        let opener = classifyFlanking(char: "*", before: nil, after: "a")
        #expect(opener.canOpen && !opener.canClose)
        let closer = classifyFlanking(char: "*", before: "a", after: nil)
        #expect(!closer.canOpen && closer.canClose)
    }

    @Test("intraword underscore can neither open nor close (K7)")
    func intrawordUnderscore() {
        let first = classifyFlanking(char: "_", before: "a", after: "b")
        #expect(!first.canOpen && !first.canClose)
    }

    @Test("underscore at the start of a word can open")
    func underscoreAtStartOpens() {
        let r = classifyFlanking(char: "_", before: nil, after: "a")
        #expect(r.canOpen && !r.canClose)
    }

    @Test("underscore with a space before is right-flanking only")
    func underscoreSpaceBefore() {
        let r = classifyFlanking(char: "_", before: "a", after: " ")
        #expect(!r.canOpen && r.canClose)
    }
}
