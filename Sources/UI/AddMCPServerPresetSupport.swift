import Foundation

enum AddMCPServerPresetSupport {
    struct Draft: Equatable {
        var id: String
        var name: String
        var iconID: String? = nil
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
        case .custom, .importJSON:
            break
        case .tinyfish:
            fillIdentityIfBlank(id: "tinyfish", name: "TinyFish", iconID: "tinyfish", draft: &draft)
            applyHTTP(endpoint: "https://agent.tinyfish.ai/mcp", authentication: .oauth, to: &draft)
        case .exaHTTP:
            fillIdentityIfBlank(id: "exa", name: "Exa", iconID: "exa", draft: &draft)
            applyHTTP(endpoint: "https://mcp.exa.ai/mcp", authentication: .none, to: &draft)
            appendPairIfMissingKey("X-Client", value: "jin", to: &draft.headerPairs, caseInsensitive: true)
        case .tavily:
            fillIdentityIfBlank(id: "tavily", name: "Tavily", iconID: "tavily", draft: &draft)
            applyHTTP(endpoint: "https://mcp.tavily.com/mcp/", authentication: .oauth, to: &draft)
        case .firecrawlLocal:
            fillIdentityIfBlank(id: "firecrawl", name: "Firecrawl", iconID: "firecrawl", draft: &draft)
            applyLocalPreset(args: "-y firecrawl-mcp", apiKey: "FIRECRAWL_API_KEY", to: &draft)
        case .exaLocal:
            fillIdentityIfBlank(id: "exa", name: "Exa", iconID: "exa", draft: &draft)
            applyLocalPreset(args: "-y exa-mcp-server", apiKey: "EXA_API_KEY", to: &draft)
        case .context7:
            fillIdentityIfBlank(id: "context7", name: "Context7", iconID: "context7", draft: &draft)
            applyHTTP(
                endpoint: "https://mcp.context7.com/mcp",
                authentication: .header(MCPHeader(name: "CONTEXT7_API_KEY", value: "", isSensitive: true)),
                to: &draft
            )
        case .playwright:
            fillIdentityIfBlank(id: "playwright", name: "Playwright", iconID: "playwright", draft: &draft)
            applyStdio(command: "npx", args: "-y @playwright/mcp@latest", to: &draft)
        case .github:
            fillIdentityIfBlank(id: "github", name: "GitHub", iconID: "github", draft: &draft)
            applyHTTP(
                endpoint: "https://api.githubcopilot.com/mcp/",
                authentication: .oauth,
                to: &draft
            )
        case .notion:
            fillIdentityIfBlank(id: "notion", name: "Notion", iconID: "notion", draft: &draft)
            applyHTTP(
                endpoint: "https://mcp.notion.com/mcp",
                authentication: .oauth,
                to: &draft
            )
        case .linear:
            fillIdentityIfBlank(id: "linear", name: "Linear", iconID: "linear", draft: &draft)
            applyHTTP(
                endpoint: "https://mcp.linear.app/mcp",
                authentication: .oauth,
                to: &draft
            )
        case .filesystem:
            fillIdentityIfBlank(id: "filesystem", name: "Filesystem", iconID: nil, draft: &draft)
            applyStdio(
                command: "npx",
                args: "-y @modelcontextprotocol/server-filesystem \(defaultFilesystemPath())",
                to: &draft
            )
        case .memory:
            fillIdentityIfBlank(id: "memory", name: "Memory", iconID: nil, draft: &draft)
            applyStdio(command: "npx", args: "-y @modelcontextprotocol/server-memory", to: &draft)
        case .sequentialThinking:
            fillIdentityIfBlank(id: "sequential-thinking", name: "Sequential Thinking", iconID: nil, draft: &draft)
            applyStdio(
                command: "npx",
                args: "-y @modelcontextprotocol/server-sequential-thinking",
                to: &draft
            )
        case .fetch:
            fillIdentityIfBlank(id: "fetch", name: "Fetch", iconID: nil, draft: &draft)
            applyStdio(command: "uvx", args: "mcp-server-fetch", to: &draft)
        }

        return draft
    }

    static func credentialValue(for preset: AddMCPServerPreset, draft: Draft) -> String {
        guard let credential = MCPServerCatalog.item(for: preset)?.credential else { return "" }

        switch credential {
        case .oauth:
            return ""
        case .bearerToken:
            if case .bearerToken(let token) = draft.httpAuthentication {
                return token
            }
            return ""
        case .header(let name, _, _):
            if case .header(let header) = draft.httpAuthentication,
               header.name.caseInsensitiveCompare(name) == .orderedSame {
                return header.value
            }
            return pairValue(named: name, in: draft.headerPairs, caseInsensitive: true) ?? ""
        case .environment(let key, _, _):
            return pairValue(named: key, in: draft.envPairs) ?? ""
        case .pathArgument:
            return filesystemPath(from: draft.args)
        }
    }

    static func applyingCredential(_ value: String, for preset: AddMCPServerPreset, to draft: Draft) -> Draft {
        guard let credential = MCPServerCatalog.item(for: preset)?.credential else { return draft }
        var draft = draft

        switch credential {
        case .oauth:
            draft.httpAuthentication = .oauth
        case .bearerToken:
            draft.httpAuthentication = value.trimmedNonEmpty == nil ? .none : .bearerToken(value)
        case .header(let name, _, _):
            if value.trimmedNonEmpty == nil {
                draft.httpAuthentication = .none
            } else {
                draft.httpAuthentication = .header(
                    MCPHeader(
                        name: name,
                        value: value,
                        isSensitive: MCPHTTPTransportConfig.isSensitiveHeaderName(name)
                    )
                )
            }
        case .environment(let key, _, _):
            upsertPair(key: key, value: value, in: &draft.envPairs)
        case .pathArgument:
            draft.args = replacingFilesystemPath(in: draft.args, with: value)
        }

        return draft
    }

    private static func applyHTTP(
        endpoint: String,
        authentication: MCPHTTPAuthentication,
        to draft: inout Draft
    ) {
        draft.transportKind = .http
        draft.endpoint = endpoint
        draft.httpAuthentication = authentication
        draft.command = ""
        draft.args = ""
    }

    private static func applyStdio(command: String, args: String, to draft: inout Draft) {
        draft.transportKind = .stdio
        draft.command = command
        draft.args = args
        draft.endpoint = ""
        draft.httpAuthentication = .none
    }

    private static func applyLocalPreset(args: String, apiKey: String, to draft: inout Draft) {
        applyStdio(command: "npx", args: args, to: &draft)
        appendPairIfMissingKey(apiKey, value: "", to: &draft.envPairs)
    }

    private static func fillIdentityIfBlank(
        id: String,
        name: String,
        iconID: String?,
        draft: inout Draft
    ) {
        if draft.id.trimmedNonEmpty == nil {
            draft.id = id
        }
        if draft.name.trimmedNonEmpty == nil {
            draft.name = name
        }
        if let iconID {
            draft.iconID = iconID
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

    private static func upsertPair(key: String, value: String, in pairs: inout [EnvironmentVariablePair]) {
        if let index = pairs.firstIndex(where: { $0.key == key }) {
            pairs[index].value = value
        } else {
            pairs.append(EnvironmentVariablePair(key: key, value: value))
        }
    }

    private static func pairValue(
        named key: String,
        in pairs: [EnvironmentVariablePair],
        caseInsensitive: Bool = false
    ) -> String? {
        pairs.first { pair in
            if caseInsensitive {
                return pair.key.caseInsensitiveCompare(key) == .orderedSame
            }
            return pair.key == key
        }?.value
    }

    static func defaultFilesystemPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .path
    }

    static func filesystemPath(from argsText: String) -> String {
        let tokens = (try? CommandLineTokenizer.tokenize(argsText)) ?? []
        guard let last = tokens.last, last != "@modelcontextprotocol/server-filesystem" else {
            return defaultFilesystemPath()
        }
        return last
    }

    static func replacingFilesystemPath(in argsText: String, with path: String) -> String {
        var tokens = (try? CommandLineTokenizer.tokenize(argsText)) ?? ["-y", "@modelcontextprotocol/server-filesystem"]
        let package = "@modelcontextprotocol/server-filesystem"
        if let index = tokens.lastIndex(of: package) {
            let pathIndex = index + 1
            let resolved = path.trimmedNonEmpty ?? defaultFilesystemPath()
            if pathIndex < tokens.count {
                tokens[pathIndex] = resolved
                tokens = Array(tokens.prefix(pathIndex + 1))
            } else {
                tokens.append(resolved)
            }
        } else {
            tokens = ["-y", package, path.trimmedNonEmpty ?? defaultFilesystemPath()]
        }
        return CommandLineTokenizer.render(tokens)
    }
}
