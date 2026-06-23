import Testing
import Foundation
@testable import Marked

@Suite("MarkdownRenderer — resolveLink")
struct LinkResolveTests {

    // MARK: - Task 5.2 tests

    @Test("valid URL → .url(URL)")
    func validURL() {
        let result = MarkdownRenderer.resolveLink("https://x.com")
        guard case .url(let url) = result else {
            Issue.record("Expected .url, got \(result)"); return
        }
        #expect(url.absoluteString == "https://x.com")
    }

    @Test("footnote: prefix → .footnote(suffix)")
    func footnoteToken() {
        let result = MarkdownRenderer.resolveLink("footnote:fn")
        guard case .footnote(let id) = result else {
            Issue.record("Expected .footnote, got \(result)"); return
        }
        #expect(id == "fn")
    }

    @Test("footnote: with longer id → .footnote(id)")
    func footnoteTokenLongId() {
        let result = MarkdownRenderer.resolveLink("footnote:my-fn-123")
        guard case .footnote(let id) = result else {
            Issue.record("Expected .footnote, got \(result)"); return
        }
        #expect(id == "my-fn-123")
    }

    @Test("empty string → .ignore")
    func emptyString() {
        let result = MarkdownRenderer.resolveLink("")
        #expect(result == .ignore)
    }

    @Test("string that URL(string:) rejects (control chars) → .ignore")
    func stringURLRejects() {
        // URL(string:) returns nil for strings with raw control characters
        let token = "http://\u{0000}bad"
        let result = MarkdownRenderer.resolveLink(token)
        #expect(result == .ignore)
    }

    @Test("relative path without scheme → .url if URL(string:) accepts it")
    func relativeToken() {
        // URL(string:) accepts "path/to/page" so it should be .url
        let token = "path/to/page"
        let result = MarkdownRenderer.resolveLink(token)
        if let _ = URL(string: token) {
            if case .url = result {
                // correct
            } else {
                Issue.record("Expected .url for '\(token)', got \(result)")
            }
        } else {
            #expect(result == .ignore)
        }
    }

    @Test("LinkAction is Equatable — two .ignore are equal")
    func linkActionEquatable() {
        #expect(LinkAction.ignore == LinkAction.ignore)
    }

    @Test("LinkAction .footnote values are Equatable")
    func linkActionFootnoteEquatable() {
        #expect(LinkAction.footnote("a") == LinkAction.footnote("a"))
        #expect(LinkAction.footnote("a") != LinkAction.footnote("b"))
    }
}
