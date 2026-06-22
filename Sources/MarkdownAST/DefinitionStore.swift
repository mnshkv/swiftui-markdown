import Foundation

/// A link reference definition collected during the block scan pass.
public struct LinkDef: Equatable, Sendable {
    public let destination: String
    public let title: String?
    public init(destination: String, title: String?) {
        self.destination = destination
        self.title = title
    }
}

/// Internal parse-time store for link reference and footnote definitions
/// collected during Pass A (block scan). Shared by reference across recursive
/// `BlockParser` calls.
///
/// Footnote bodies are stored as raw lines here; they are resolved into
/// `FootnoteDefinition` values later in Pass B (inline resolution), so this
/// store deliberately does NOT expose `[FootnoteDefinition]`.
final class DefinitionStore {

    /// A footnote definition awaiting inline resolution in Pass B.
    struct PendingFootnote: Equatable {
        let id: String
        let bodyLines: [String]
    }

    /// Link reference definitions keyed by normalized label. First definition wins.
    private var links: [String: LinkDef] = [:]

    /// Footnote definitions in insertion order, raw bodies pending Pass B resolution.
    private(set) var pendingFootnotes: [PendingFootnote] = []

    init() {}

    /// Normalize a CommonMark link label: trim, lowercase, collapse internal
    /// runs of whitespace (spaces/tabs/newlines) to a single space.
    static func normalize(_ label: String) -> String {
        var result = ""
        result.reserveCapacity(label.count)
        var lastWasSpace = true  // true so leading whitespace is dropped
        for ch in label {
            if ch.isWhitespace {
                lastWasSpace = true
            } else {
                if lastWasSpace && !result.isEmpty {
                    result.append(" ")
                }
                result.append(ch.lowercased())
                lastWasSpace = false
            }
        }
        return result
    }

    // MARK: - Links

    /// Register a link reference definition. First definition for a label wins;
    /// subsequent registrations for the same (normalized) label are ignored.
    func addLink(label: String, destination: String, title: String?) {
        let key = Self.normalize(label)
        guard key != "" else { return }
        if links[key] != nil { return }
        links[key] = LinkDef(destination: destination, title: title)
    }

    /// Look up a link reference definition by (possibly non-normalized) label.
    func link(for label: String) -> LinkDef? {
        links[Self.normalize(label)]
    }

    // MARK: - Footnotes

    /// Record a footnote body as raw lines (Pass A). Resolution into
    /// `FootnoteDefinition` happens in Pass B.
    func addFootnote(id: String, bodyLines: [String]) {
        pendingFootnotes.append(PendingFootnote(id: id, bodyLines: bodyLines))
    }

    /// True iff a footnote with the given id has been registered.
    func hasFootnote(_ id: String) -> Bool {
        pendingFootnotes.contains { $0.id == id }
    }
}
