import Foundation

enum MCPServerFormSupport {
    static func parsedEndpoint(_ endpoint: String) -> URL? {
        guard let trimmed = endpoint.trimmedNonEmpty,
              let url = URL(string: trimmed),
              url.scheme != nil else {
            return nil
        }
        return url
    }

    static func isAddServerDisabled(
        name: String,
        transportKind: MCPTransportKind,
        command: String,
        parsedEndpoint: URL?,
        parsedHTTPAuthentication: MCPHTTPAuthentication?
    ) -> Bool {
        guard name.trimmedNonEmpty != nil else { return true }

        switch transportKind {
        case .stdio:
            return command.trimmedNonEmpty == nil
        case .http:
            return parsedEndpoint == nil || parsedHTTPAuthentication == nil
        }
    }

    static func hasTransportValidationError(
        transportKind: MCPTransportKind,
        command: String,
        argsError: String?,
        endpoint: String,
        endpointError: String?,
        httpAuthenticationValidationError: String?
    ) -> Bool {
        switch transportKind {
        case .stdio:
            return command.trimmedNonEmpty == nil || argsError != nil
        case .http:
            return endpoint.trimmedNonEmpty == nil
                || endpointError != nil
                || httpAuthenticationValidationError != nil
        }
    }

    static func shouldShowNodeIsolationNote(command: String) -> Bool {
        let trimmed = command.trimmedNonEmpty ?? ""
        let parsedCommand = (try? CommandLineTokenizer.tokenize(trimmed))?.first ?? trimmed
        let base = (parsedCommand as NSString).lastPathComponent.lowercased()
        return ["npx", "npm", "pnpm", "yarn", "bunx", "bun"].contains(base)
    }

    static func isFirecrawlMCP(command: String, argsText: String) -> Bool {
        let cmd = command.lowercased()
        if cmd.contains("firecrawl-mcp") { return true }

        let args = (try? CommandLineTokenizer.tokenize(argsText)) ?? []
        return args.contains { $0.lowercased() == "firecrawl-mcp" }
    }

    static func hasFirecrawlAPIKey(in pairs: [EnvironmentVariablePair]) -> Bool {
        pairs.contains { pair in
            pair.key.trimmedNonEmpty == "FIRECRAWL_API_KEY"
                && pair.value.trimmedNonEmpty != nil
        }
    }

    static func normalizedServerID(_ id: String, fallback: () -> String = { UUID().uuidString }) -> String {
        id.trimmedNonEmpty ?? fallback()
    }

    static func normalizedServerName(_ name: String?, fallback: String) -> String {
        name?.trimmedNonEmpty ?? fallback
    }

    static func normalizedIconID(_ iconID: String?, defaultIconID: String = MCPIconCatalog.defaultIconID) -> String? {
        guard let trimmedIconID = iconID?.trimmedNonEmpty else { return nil }
        if trimmedIconID.caseInsensitiveCompare(defaultIconID) == .orderedSame {
            return nil
        }
        return trimmedIconID
    }

    static func environmentDictionary(from pairs: [EnvironmentVariablePair]) -> [String: String] {
        pairs.reduce(into: [:]) { partial, pair in
            guard let key = pair.key.trimmedNonEmpty else { return }
            partial[key] = pair.value
        }
    }

    static func headers(from pairs: [EnvironmentVariablePair]) -> [MCPHeader] {
        pairs.compactMap { pair in
            header(name: pair.key, value: pair.value)
        }
    }

    static func header(name: String, value: String) -> MCPHeader? {
        guard let key = name.trimmedNonEmpty else { return nil }
        return MCPHeader(
            name: key,
            value: value,
            isSensitive: MCPHTTPTransportConfig.isSensitiveHeaderName(key)
        )
    }
}
