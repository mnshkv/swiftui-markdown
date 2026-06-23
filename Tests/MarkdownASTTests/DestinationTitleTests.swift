import Testing
@testable import MarkdownAST

@Suite("Link destination & title parsing")
struct DestinationTitleTests {
    @Test("destination and double-quoted title")
    func destAndTitle() {
        let r = splitDestinationAndTitle("https://a.com \"T\"")
        #expect(r?.dest == "https://a.com")
        #expect(r?.title == "T")
    }

    @Test("angle-bracket destination keeps inner spaces")
    func angleDestWithSpaces() {
        let r = splitDestinationAndTitle("<https://a.com/x y> \"T\"")
        #expect(r?.dest == "https://a.com/x y")
        #expect(r?.title == "T")
    }

    @Test("balanced parens in a bare destination")
    func balancedParensInDest() {
        let r = splitDestinationAndTitle("https://a.com/(x)")
        #expect(r?.dest == "https://a.com/(x)")
        #expect(r?.title == nil)
    }

    @Test("single-quoted and parenthesized titles")
    func altTitleDelimiters() {
        #expect(splitDestinationAndTitle("https://a.com 'T'")?.title == "T")
        #expect(splitDestinationAndTitle("https://a.com (T)")?.title == "T")
    }

    @Test("leftover junk after the title is rejected")
    func leftoverJunkRejected() {
        #expect(splitDestinationAndTitle("https://a.com \"T\" junk") == nil)
    }

    @Test("a title with no destination is invalid")
    func onlyTitleInvalid() {
        #expect(splitDestinationAndTitle("\"only title\"") == nil)
    }
}
