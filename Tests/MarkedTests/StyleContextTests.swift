import Testing
import CoreGraphics
@testable import Marked

@Suite("StyleContext")
struct StyleContextTests {
    @Test("light vs dark resolve different text colors; heading is bold and bigger")
    func resolves() {
        let light = StyleContext(.default, .light)
        let dark = StyleContext(.default, .dark)
        #expect(light.body.color != dark.body.color)
        #expect(light.heading(1).isBold)
        #expect(light.heading(1).fontSize > light.body.fontSize)
        #expect(light.heading(9).fontSize == light.heading(6).fontSize)  // clamped
        #expect(light.inlineCode.isMonospace)
    }
}
