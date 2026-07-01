// Tests/MarkedTests/InlineRuleEngineTests.swift
import Testing
import CoreGraphics
@testable import Marked

@Suite("InlineRuleEngine")
struct InlineRuleEngineTests {
    let ctx = StyleContext(.default, .light)
    var base: TextStyle { ctx.body }

    let hashtag = InlineRule(id: "hashtag", trigger: "#",
        output: .styledText(InlineDecoration(color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))))
    let mention = InlineRule(id: "mention", trigger: "@",
        output: .styledText(InlineDecoration(isBold: true)))
    let emoji = InlineRule(id: "emoji", trigger: ":", closing: ":",
        output: .image(keyPrefix: "emoji:"), isTappable: false)

    func apply(_ s: String, _ rules: [InlineRule]) -> [InlineRun] {
        InlineRuleEngine.apply(s, rules: rules, base: base, ctx: ctx)
    }

    @Test("no rules → single text run unchanged")
    func passthrough() {
        let runs = InlineRuleEngine.apply("plain #x", rules: [], base: base, ctx: ctx)
        #expect(runs == [.text("plain #x", base)])
    }

    @Test("hashtag becomes a tappable blue text run with the # kept")
    func hashtagMatch() {
        let runs = apply("hi #swift!", [hashtag])
        #expect(runs.count == 3)
        guard case .text(let pre, _) = runs[0] else { Issue.record("pre"); return }
        #expect(pre == "hi ")
        guard case .link(let inner, let payload) = runs[1] else { Issue.record("link"); return }
        guard case .text(let disp, let st) = inner.first else { Issue.record("inner"); return }
        #expect(disp == "#swift")
        #expect(st.color == CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        #expect(InlineRuleToken.decode(payload.token)?.value == "swift")
        guard case .text(let post, _) = runs[2] else { Issue.record("post"); return }
        #expect(post == "!")
    }

    @Test("leading boundary: email@host does not match @mention")
    func leadingBoundary() {
        #expect(apply("email@host", [mention]) == [.text("email@host", base)])
    }

    @Test("@ at start of text matches and is bold")
    func mentionAtStart() {
        let runs = apply("@alice", [mention])
        guard case .link(let inner, _) = runs.first else { Issue.record("link"); return }
        guard case .text(let disp, let st) = inner.first else { Issue.record("inner"); return }
        #expect(disp == "@alice")
        #expect(st.isBold)
    }

    @Test("emoji shortcode becomes an inline image; trigger and delimiters dropped")
    func emojiMatch() {
        let runs = apply("hi :smile: there", [emoji])
        #expect(runs.count == 3)
        guard case .inlineImage(let att) = runs[1] else { Issue.record("image"); return }
        #expect(att.source == "emoji:smile")
        #expect(att.alt == "smile")
    }

    @Test("closing delimiter required: ':smile' without closing colon does not match")
    func emojiNeedsClosing() {
        #expect(apply(":smile", [emoji]) == [.text(":smile", base)])
    }

    @Test("empty body: a bare '#' with a following space does not match")
    func emptyBody() {
        #expect(apply("a # b", [hashtag]) == [.text("a # b", base)])
    }

    @Test("rule order is precedence: first matching rule wins")
    func precedence() {
        let a = InlineRule(id: "first", trigger: "#",
            output: .styledText(InlineDecoration(isBold: true)))
        let b = InlineRule(id: "second", trigger: "#",
            output: .styledText(InlineDecoration(isItalic: true)))
        let runs = apply("#x", [a, b])
        guard case .link(_, let payload) = runs.first else { Issue.record("link"); return }
        #expect(InlineRuleToken.decode(payload.token)?.ruleID == "first")
    }

    @Test("background decoration flows into the run's TextStyle.background")
    func pillStyle() {
        let green = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        let r = InlineRule(id: "tag", trigger: "#",
            output: .styledText(InlineDecoration(background: green)), isTappable: false)
        let runs = apply("#x", [r])
        guard case .text(_, let st) = runs.first else { Issue.record("text"); return }
        #expect(st.background == green)
    }

    @Test("includeTrigger false drops the trigger from display text")
    func dropTrigger() {
        let r = InlineRule(id: "bare", trigger: "#",
            output: .styledText(InlineDecoration(includeTrigger: false)), isTappable: false)
        let runs = apply("#x", [r])
        guard case .text(let disp, _) = runs.first else { Issue.record("text"); return }
        #expect(disp == "x")
    }
}
