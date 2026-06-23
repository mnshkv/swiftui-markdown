import Testing
@testable import MarkdownAST

@Suite("Adjacent text coalescing")
struct CoalescingTests {
    @Test("adjacent text nodes merge into one")
    func mergeAdjacentText() {
        let out = coalesceText([.text("a "), .text("*"), .text(" b")])
        #expect(out == [.text("a * b")])
    }

    @Test("text inside emphasis is coalesced recursively")
    func coalesceInsideEmphasis() {
        let out = coalesceText([.text("x"), .emphasis([.text("a"), .text("b")]), .text("y")])
        #expect(out == [.text("x"), .emphasis([.text("ab")]), .text("y")])
    }
}
