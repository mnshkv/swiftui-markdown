import Testing
@testable import MarkdownAST

@Suite("Container/indentation helpers")
struct ContainersTests {

    // MARK: - stripUpTo3Spaces

    @Test("3 leading spaces are dropped")
    func strip3Spaces() {
        #expect(stripUpTo3Spaces("   # H") == "# H")
    }

    @Test("4 leading spaces are kept (indented-code must stay detectable)")
    func strip4SpacesKept() {
        #expect(stripUpTo3Spaces("    code") == "    code")
    }

    @Test("empty string yields empty")
    func stripEmpty() {
        #expect(stripUpTo3Spaces("") == "")
    }

    @Test("no leading spaces yields unchanged")
    func stripNone() {
        #expect(stripUpTo3Spaces("# H") == "# H")
    }

    @Test("2 leading spaces dropped")
    func strip2Spaces() {
        #expect(stripUpTo3Spaces("  x") == "x")
    }

    // MARK: - isBlockStart

    @Test("ATX heading is block start")
    func atxIsBlockStart() {
        #expect(isBlockStart("# H"))
        #expect(isBlockStart("## H ##"))
    }

    @Test("plain text is not block start")
    func plainTextNotBlockStart() {
        #expect(!isBlockStart("plain text"))
    }

    @Test("blockquote is block start")
    func blockquoteIsBlockStart() {
        #expect(isBlockStart("> quote"))
    }

    @Test("thematic break is block start")
    func thematicBreakIsBlockStart() {
        #expect(isBlockStart("- - -"))
    }

    @Test("underscore-led thematic break is block start")
    func underscoreThematicBreakIsBlockStart() {
        #expect(isBlockStart("___"))
        #expect(isBlockStart("_ _ _"))
        #expect(!isBlockStart("_not_a_break"))
    }

    @Test("indented (4-space) code is NOT block start")
    func indentedCodeNotBlockStart() {
        #expect(!isBlockStart("    code"))
    }

    @Test("fenced code is block start")
    func fenceIsBlockStart() {
        #expect(isBlockStart("```"))
        #expect(isBlockStart("~~~"))
    }

    @Test("setext underline is block start")
    func setextIsBlockStart() {
        #expect(isBlockStart("=== "))
    }

    @Test("list marker is block start")
    func listMarkerIsBlockStart() {
        #expect(isBlockStart("- item"))
    }

    // MARK: - canInterruptParagraph

    @Test("ordered start with number 2 does not interrupt")
    func ordered2NoInterrupt() {
        #expect(!canInterruptParagraph("2. x"))
    }

    @Test("unordered list interrupts")
    func unorderedInterrupts() {
        #expect(canInterruptParagraph("- x"))
    }

    @Test("ordered start with number 1 interrupts")
    func ordered1Interrupts() {
        #expect(canInterruptParagraph("1. x"))
    }

    @Test("empty item (marker then whitespace only) does not interrupt")
    func emptyItemNoInterrupt() {
        #expect(!canInterruptParagraph("-   "))
    }

    @Test("ordered start with number 10 does not interrupt")
    func ordered10NoInterrupt() {
        #expect(!canInterruptParagraph("10. x"))
    }

    @Test("ordered start with 1) paren interrupts")
    func ordered1ParenInterrupts() {
        #expect(canInterruptParagraph("1) x"))
    }

    @Test("plus marker interrupts")
    func plusInterrupts() {
        #expect(canInterruptParagraph("+ y"))
    }

    @Test("setext underline does NOT interrupt (it converts, handled elsewhere)")
    func setextNoInterrupt() {
        #expect(!canInterruptParagraph("=== "))
    }

    @Test("ATX heading interrupts")
    func atxInterrupts() {
        #expect(canInterruptParagraph("# H"))
    }

    @Test("blockquote interrupts")
    func blockquoteInterrupts() {
        #expect(canInterruptParagraph("> q"))
    }

    @Test("fenced code interrupts")
    func fenceInterrupts() {
        #expect(canInterruptParagraph("```"))
    }

    @Test("thematic break interrupts")
    func thematicInterrupts() {
        #expect(canInterruptParagraph("- - -"))
    }

    @Test("underscore-led thematic break interrupts")
    func underscoreThematicInterrupts() {
        #expect(canInterruptParagraph("___"))
        #expect(canInterruptParagraph("_ _ _"))
    }

    @Test("indented code (4-space) does not interrupt")
    func indentedCodeNoInterrupt() {
        #expect(!canInterruptParagraph("    code"))
    }

    @Test("plain text does not interrupt")
    func plainTextNoInterrupt() {
        #expect(!canInterruptParagraph("plain text"))
    }
}
