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
