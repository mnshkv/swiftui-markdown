import Testing
@testable import MarkdownAST

@Suite("List marker recognizer (CommonMark §5.1)")
struct ListMarkerTests {

    @Test("bullet dash")
    func bulletDash() {
        let m = listMarker(Substring("- x"))
        #expect(m != nil)
        #expect(m?.kind == .bullet)
        #expect(m?.bullet == "-")
        #expect(m?.leadingIndent == 0)
        #expect(m?.markerWidth == 2)
    }

    @Test("bullet plus")
    func bulletPlus() {
        let m = listMarker(Substring("+ x"))
        #expect(m?.kind == .bullet)
        #expect(m?.bullet == "+")
        #expect(m?.markerWidth == 2)
    }

    @Test("bullet star")
    func bulletStar() {
        let m = listMarker(Substring("* x"))
        #expect(m?.kind == .bullet)
        #expect(m?.bullet == "*")
        #expect(m?.markerWidth == 2)
    }

    @Test("ordered dot")
    func orderedDot() {
        let m = listMarker(Substring("1. x"))
        #expect(m?.kind == .ordered(start: 1))
        #expect(m?.orderedDelimiter == ".")
        #expect(m?.start == 1)
        #expect(m?.markerWidth == 3)
    }

    @Test("ordered paren")
    func orderedParen() {
        let m = listMarker(Substring("1) x"))
        #expect(m?.kind == .ordered(start: 1))
        #expect(m?.orderedDelimiter == ")")
        #expect(m?.start == 1)
        #expect(m?.markerWidth == 3)
    }

    @Test("ordered start 3")
    func orderedStart3() {
        let m = listMarker(Substring("3. x"))
        #expect(m?.kind == .ordered(start: 3))
        #expect(m?.start == 3)
        #expect(m?.markerWidth == 3)
    }

    @Test("ordered nine digits")
    func orderedNineDigits() {
        let m = listMarker(Substring("123456789. x"))
        #expect(m?.kind == .ordered(start: 123456789))
        #expect(m?.start == 123456789)
        #expect(m?.markerWidth == 11)
    }

    @Test("ordered ten digits -> nil")
    func orderedTenDigitsNil() {
        let m = listMarker(Substring("1234567890. x"))
        #expect(m == nil)
    }

    @Test("markerWidth one space")
    func markerWidthOneSpace() {
        let m = listMarker(Substring("- x"))
        #expect(m?.markerWidth == 2)
    }

    @Test("markerWidth three spaces")
    func markerWidthThreeSpaces() {
        let m = listMarker(Substring("-   x"))
        #expect(m?.markerWidth == 4)
    }

    @Test("markerWidth five spaces cap")
    func markerWidthFiveSpacesCap() {
        let m = listMarker(Substring("-     x"))
        #expect(m?.markerWidth == 2)
    }

    @Test("markerWidth four spaces")
    func markerWidthFourSpaces() {
        let m = listMarker(Substring("-    x"))
        #expect(m?.markerWidth == 5)
    }

    @Test("four-space leading indent -> nil")
    func fourSpaceLeadingIndentNil() {
        let m = listMarker(Substring("    - x"))
        #expect(m == nil)
    }

    @Test("three-space leading indent ok")
    func threeSpaceLeadingIndentOk() {
        let m = listMarker(Substring("   - x"))
        #expect(m != nil)
        #expect(m?.leadingIndent == 3)
        #expect(m?.markerWidth == 2)
    }

    @Test("no space after bullet -> nil")
    func noSpaceAfterBulletNil() {
        let m = listMarker(Substring("-"))
        #expect(m == nil)
    }

    @Test("bullet with empty content")
    func bulletWithEmptyContent() {
        let m = listMarker(Substring("- "))
        #expect(m != nil)
        #expect(m?.markerWidth == 2)
    }

    @Test("ordered no space -> nil")
    func orderedNoSpaceNil() {
        let m = listMarker(Substring("1."))
        #expect(m == nil)
    }

    @Test("not a marker")
    func notAMarker() {
        #expect(listMarker(Substring("foo")) == nil)
        #expect(listMarker(Substring("# H")) == nil)
    }

    @Test("dash dash not a marker")
    func dashDashNotMarker() {
        let m = listMarker(Substring("-- x"))
        #expect(m == nil)
    }

    @Test("ordered two spaces")
    func orderedTwoSpaces() {
        let m = listMarker(Substring("1.  x"))
        #expect(m?.markerWidth == 4)
    }

    @Test("contentStart is leadingIndent + markerWidth")
    func contentStartField() {
        let m = listMarker(Substring("   -   x"))
        #expect(m?.leadingIndent == 3)
        #expect(m?.markerWidth == 4)
        #expect(m?.contentStart == 7)
    }

    @Test("pure recognizer: '- - x' is a marker (no thematic adjudication)")
    func pureDashDashX() {
        let m = listMarker(Substring("- - x"))
        #expect(m != nil)
        #expect(m?.kind == .bullet)
        #expect(m?.bullet == "-")
        #expect(m?.markerWidth == 2)
    }
}
