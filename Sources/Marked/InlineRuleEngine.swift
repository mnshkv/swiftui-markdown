// Sources/Marked/InlineRuleEngine.swift
import CoreGraphics

/// Applies a set of `InlineRule`s to a plain-text string, producing a mix of
/// plain-text, styled-text, inline-image and tappable runs. Pure and synchronous.
enum InlineRuleEngine {

    /// Splits `s` into runs, replacing rule matches with their styled/image output.
    /// `base` is the surrounding text style so matches inherit emphasis, colour, etc.
    static func apply(
        _ s: String,
        rules: [InlineRule],
        base: TextStyle,
        ctx: StyleContext
    ) -> [InlineRun] {
        guard !rules.isEmpty, !s.isEmpty else { return [.text(s, base)] }

        let chars = Array(s)
        var runs: [InlineRun] = []
        var buf = ""
        var i = 0

        func flush() {
            if !buf.isEmpty { runs.append(.text(buf, base)); buf = "" }
        }

        while i < chars.count {
            let c = chars[i]
            var matched = false
            // First rule (array order = precedence) that matches at i wins.
            for rule in rules where rule.trigger == c {
                if rule.requiresLeadingBoundary, i > 0, isWordChar(chars[i - 1]) {
                    continue
                }
                guard let m = match(rule, chars, from: i) else { continue }
                flush()
                runs.append(makeRun(rule, value: m.body, base: base, ctx: ctx))
                i = m.end
                matched = true
                break
            }
            if matched { continue }
            buf.append(c)
            i += 1
        }
        flush()
        return runs
    }

    // MARK: - Matching

    private static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    /// Attempts to match `rule` at `start` (the trigger char). Returns the body
    /// text and the index just past the whole match.
    private static func match(
        _ rule: InlineRule, _ chars: [Character], from start: Int
    ) -> (body: String, end: Int)? {
        var j = start + 1
        var body = ""
        while j < chars.count, rule.body.contains(chars[j]) {
            body.append(chars[j]); j += 1
        }
        guard body.count >= rule.minBodyLength else { return nil }
        if let close = rule.closing {
            guard j < chars.count, chars[j] == close else { return nil }
            j += 1  // consume closing delimiter
        }
        return (body, j)
    }

    // MARK: - Run construction

    private static func makeRun(
        _ rule: InlineRule, value: String, base: TextStyle, ctx: StyleContext
    ) -> InlineRun {
        let inner: InlineRun
        switch rule.output {
        case .styledText(let d):
            var st = base
            if let color = d.color { st.color = color }
            if d.isBold { st.isBold = true }
            if d.isItalic { st.isItalic = true }
            st.background = d.background
            let display = (d.includeTrigger ? String(rule.trigger) : "") + value
            inner = .text(display, st)
        case .image(let keyPrefix):
            inner = .inlineImage(ImageAttachment(
                source: keyPrefix + value,
                intrinsicSize: ctx.style.inlineImageSize,
                alt: value
            ))
        }
        guard rule.isTappable else { return inner }
        return .link(runs: [inner],
                     payload: LinkPayload(InlineRuleToken.encode(ruleID: rule.id, value: value)))
    }
}
