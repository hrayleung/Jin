import Foundation

/// A Modal proxy token: the `wk-…` ID and `ws-…` secret pair printed by
/// `modal workspace proxy-tokens create`.
///
/// Modal accepts the pair two equivalent ways (modal.com/docs/guide/endpoints):
/// joined with a `.` in a single `Authorization: Bearer` header, or split across
/// `Modal-Key` and `Modal-Secret`. Jin stores the joined form in the existing
/// single-credential field so no persistence change is needed, and splits it
/// again for the two entry fields and for the request headers.
struct ModalProxyToken: Equatable {
    static let idPrefix = "wk-"
    static let secretPrefix = "ws-"
    /// Header names Modal's proxy accepts as an alternative to `Authorization`.
    static let keyHeaderName = "Modal-Key"
    static let secretHeaderName = "Modal-Secret"

    let id: String
    let secret: String

    var combined: String {
        "\(id).\(secret)"
    }

    /// Parses a stored credential into its two halves.
    ///
    /// Accepts the documented joined form (`wk-abc.ws-def`) as well as the two
    /// halves pasted with whitespace or a `:`/`,`/`;` between them, which is how
    /// they arrive when copied out of the CLI or dashboard. Returns nil for
    /// anything else so a non-Modal credential is never silently reshaped.
    static func parse(_ rawValue: String) -> ModalProxyToken? {
        let trimmed = rawValue.trimmed
        guard trimmed.hasPrefix(idPrefix) else { return nil }

        let separators = CharacterSet(charactersIn: ":,;").union(.whitespacesAndNewlines)
        let parts = trimmed
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }

        switch parts.count {
        case 1:
            // Joined form: split at the secret prefix, which cannot appear earlier
            // because the ID prefix is `wk-`.
            guard let range = parts[0].range(of: ".\(secretPrefix)") else { return nil }
            let id = String(parts[0][parts[0].startIndex..<range.lowerBound])
            let secret = String(parts[0][parts[0].index(after: range.lowerBound)...])
            return make(id: id, secret: secret)
        case 2:
            return make(id: parts[0], secret: parts[1])
        default:
            return nil
        }
    }

    /// Normalizes a credential for storage: a recognizable pair becomes the joined
    /// form, anything else is passed through trimmed but otherwise untouched.
    static func normalized(_ rawValue: String) -> String {
        parse(rawValue)?.combined ?? rawValue.trimmed
    }

    /// Rebuilds the stored credential from the two entry fields. An incomplete
    /// pair stores just what has been typed so far rather than a broken `wk-abc.`.
    static func storedValue(id: String, secret: String) -> String {
        let trimmedID = id.trimmed
        let trimmedSecret = secret.trimmed

        if trimmedID.isEmpty { return trimmedSecret }
        if trimmedSecret.isEmpty { return trimmedID }
        return "\(trimmedID).\(trimmedSecret)"
    }

    /// Splits a stored credential for display in the two entry fields. Falls back
    /// to putting the whole value in the ID field so a partially typed or
    /// unrecognized credential is never dropped.
    static func fields(from rawValue: String) -> (id: String, secret: String) {
        if let token = parse(rawValue) {
            return (token.id, token.secret)
        }
        return (rawValue.trimmed, "")
    }

    private static func make(id: String, secret: String) -> ModalProxyToken? {
        guard id.hasPrefix(idPrefix), id.count > idPrefix.count,
              secret.hasPrefix(secretPrefix), secret.count > secretPrefix.count else {
            return nil
        }
        return ModalProxyToken(id: id, secret: secret)
    }
}
