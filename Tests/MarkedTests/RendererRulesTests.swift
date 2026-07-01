// Tests/MarkedTests/RendererRulesTests.swift
import Testing
import CoreGraphics
@testable import Marked

@Suite("MarkdownRenderer with custom rules")
struct RendererRulesTests {
    @Test("render threads rules so a hashtag paragraph contains a tappable rule run")
    func hashtagRendered() {
        let rule = InlineRule(id: "hashtag", trigger: "#",
            output: .styledText(InlineDecoration(isBold: true)))
        let doc = MarkdownRenderer.render("#swift", rules: [rule])
        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        let hasRuleLink = p.runs.contains { run in
            if case .link(_, let payload) = run {
                return InlineRuleToken.decode(payload.token)?.ruleID == "hashtag"
            }
            return false
        }
        #expect(hasRuleLink)
    }

    @Test("without rules a hashtag stays plain text (no link runs)")
    func noRules() {
        let doc = MarkdownRenderer.render("#swift")
        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        for run in p.runs {
            if case .link = run { Issue.record("should be no link run"); return }
        }
    }
}
