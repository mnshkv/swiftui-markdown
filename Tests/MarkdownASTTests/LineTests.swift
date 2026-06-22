import Testing
@testable import MarkdownAST

@Suite("Line preprocessing")
struct LineTests {
    // MARK: splitIntoLines

    @Test("splits on all line endings (\\n, \\r\\n, \\r)")
    func splitsOnAllLineEndings() {
        #expect(splitIntoLines("a\nb\r\nc\rd") == ["a", "b", "c", "d"])
    }

    @Test("preserves blank lines in middle but not trailing newline")
    func preservesBlankLinesButNotTrailingNewline() {
        #expect(splitIntoLines("a\n\nb\n") == ["a", "", "b"])
    }

    @Test("empty string yields no lines")
    func emptyStringIsNoLines() {
        #expect(splitIntoLines("").isEmpty)
    }

    // MARK: expandTabs

    @Test("tab at column 0 expands to four-space stop")
    func tabsExpandToFourColStop() {
        #expect(expandTabs("\t# H") == "    # H")
        #expect(expandTabs("a\tb") == "a   b")
    }

    @Test("midline tab aligns to next multiple of tabWidth")
    func tabMidlineAlignsToNextMultiple() {
        #expect(expandTabs("ab\tcd") == "ab  cd")
    }
}
