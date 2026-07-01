/// Encodes/decodes the opaque `LinkPayload.token` used to route custom-rule taps
/// through the existing link machinery. Uses U+0001 (SOH) separators, which
/// cannot occur in Markdown source text.
enum InlineRuleToken {
    static let prefix = "\u{1}rule\u{1}"

    /// Builds the payload token for a tappable custom-rule span.
    static func encode(ruleID: String, value: String) -> String {
        "\(prefix)\(ruleID)\u{1}\(value)"
    }

    /// Decodes a token produced by `encode`. Returns nil if `token` is not a
    /// custom-rule token.
    static func decode(_ token: String) -> (ruleID: String, value: String)? {
        guard token.hasPrefix(prefix) else { return nil }
        let rest = token.dropFirst(prefix.count)
        guard let sep = rest.firstIndex(of: "\u{1}") else { return nil }
        let ruleID = String(rest[rest.startIndex..<sep])
        let value = String(rest[rest.index(after: sep)...])
        return (ruleID, value)
    }
}
