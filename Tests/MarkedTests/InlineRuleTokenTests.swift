// Tests/MarkedTests/InlineRuleTokenTests.swift
import Testing
import Foundation
@testable import Marked

@Suite("Custom-rule tap round-trip")
struct InlineRuleTokenTests {
    @Test("encode then decode recovers ruleID and value")
    func roundTrip() {
        let t = InlineRuleToken.encode(ruleID: "hashtag", value: "swift")
        let d = InlineRuleToken.decode(t)
        #expect(d?.ruleID == "hashtag")
        #expect(d?.value == "swift")
    }

    @Test("decode returns nil for non-rule tokens")
    func decodeNonRule() {
        #expect(InlineRuleToken.decode("https://swift.org")?.ruleID == nil)
        #expect(InlineRuleToken.decode("footnote:1")?.ruleID == nil)
    }

    @Test("resolveLink maps a rule token to .custom")
    func resolveCustom() {
        let token = InlineRuleToken.encode(ruleID: "mention", value: "alice")
        #expect(MarkdownRenderer.resolveLink(token) == .custom(ruleID: "mention", value: "alice"))
    }

    @Test("resolveLink still maps a URL to .url")
    func resolveURLStillWorks() {
        #expect(MarkdownRenderer.resolveLink("https://swift.org") == .url(URL(string: "https://swift.org")!))
    }

    @Test("resolveLink still maps a footnote token to .footnote")
    func resolveFootnoteStillWorks() {
        #expect(MarkdownRenderer.resolveLink("footnote:x") == .footnote("x"))
    }
}
