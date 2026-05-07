import Foundation

enum AddMCPServerPresetSupport {
    struct Draft: Equatable {
        var id: String
        var name: String
        var transportKind: MCPTransportKind
        var command: String
        var args: String
        var envPairs: [EnvironmentVariablePair]
        var endpoint: String
        var headerPairs: [EnvironmentVariablePair]
        var httpAuthentication: MCPHTTPAuthentication
    }

    static func canImportJSON(_ importJSON: String) -> Bool {
        importJSON.trimmedNonEmpty != nil
    }

    static func applyingPreset(_ preset: AddMCPServerPreset, to draft: Draft) -> Draft {
        var draft = draft

        switch preset {
        case .custom:
            break
        case .exaHTTP:
            fillIdentityIfBlank(id: "exa", name: "Exa", draft: &draft)
            draft.transportKind = .http
            draft.endpoint = "https://mcp.exa.ai/mcp"
            draft.httpAuthentication = .none
            appendPairIfMissingKey("X-Client", value: "jin", to: &draft.headerPairs, caseInsensitive: true)
        case .exaLocal:
            fillIdentityIfBlank(id: "exa", name: "Exa", draft: &draft)
            applyLocalPreset(args: "-y exa-mcp-server", apiKey: "EXA_API_KEY", to: &draft)
        case .firecrawlLocal:
            fillIdentityIfBlank(id: "firecrawl", name: "Firecrawl", draft: &draft)
            applyLocalPreset(args: "-y firecrawl-mcp", apiKey: "FIRECRAWL_API_KEY", to: &draft)
        }

        return draft
    }

    private static func applyLocalPreset(args: String, apiKey: String, to draft: inout Draft) {
        draft.transportKind = .stdio
        draft.command = "npx"
        draft.args = args
        appendPairIfMissingKey(apiKey, value: "", to: &draft.envPairs)
    }

    private static func fillIdentityIfBlank(id: String, name: String, draft: inout Draft) {
        if draft.id.trimmedNonEmpty == nil {
            draft.id = id
        }
        if draft.name.trimmedNonEmpty == nil {
            draft.name = name
        }
    }

    private static func appendPairIfMissingKey(
        _ key: String,
        value: String,
        to pairs: inout [EnvironmentVariablePair],
        caseInsensitive: Bool = false
    ) {
        let hasKey = pairs.contains { pair in
            if caseInsensitive {
                return pair.key.caseInsensitiveCompare(key) == .orderedSame
            }
            return pair.key == key
        }

        if !hasKey {
            pairs.append(EnvironmentVariablePair(key: key, value: value))
        }
    }
}
