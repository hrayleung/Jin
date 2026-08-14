import Foundation

/// Parses `npx -y mcp-remote <url> --header ...` into Jin's native HTTP transport.
///
/// Claude Desktop and many READMEs still ship remote MCP servers as a stdio
/// `mcp-remote` proxy. Jin already speaks Streamable HTTP, so that extra Node
/// process is unnecessary and is a common source of npm / SIGTERM failures.
struct MCPRemoteProxyCommand: Equatable, Sendable {
    let endpoint: URL
    let headers: [MCPHeader]

    var httpTransport: MCPHTTPTransportConfig {
        var authentication = MCPHTTPAuthentication.none
        var remaining = headers

        if let authIndex = remaining.firstIndex(where: {
            $0.name.caseInsensitiveCompare("Authorization") == .orderedSame
        }) {
            let auth = remaining.remove(at: authIndex)
            if let token = bearerToken(from: auth.value) {
                authentication = .bearerToken(token)
            } else {
                authentication = .header(auth)
            }
        }

        return MCPHTTPTransportConfig(
            endpoint: endpoint,
            streaming: true,
            authentication: authentication,
            additionalHeaders: remaining
        )
    }

    private func bearerToken(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("bearer ") else { return nil }
        return String(trimmed.dropFirst("bearer ".count)).trimmedNonEmpty
    }

    static func parse(command: String, args: [String]) -> MCPRemoteProxyCommand? {
        let commandTokens = (try? CommandLineTokenizer.tokenize(command)) ?? []
        return parse(tokens: commandTokens + args)
    }

    static func parse(commandLine: String, argsText: String) -> MCPRemoteProxyCommand? {
        let commandTokens = (try? CommandLineTokenizer.tokenize(commandLine)) ?? []
        let argTokens = (try? CommandLineTokenizer.tokenize(argsText)) ?? []
        return parse(tokens: commandTokens + argTokens)
    }

    static func parse(tokens: [String]) -> MCPRemoteProxyCommand? {
        guard let remoteIndex = tokens.firstIndex(where: isMCPRemotePackage) else {
            return nil
        }

        let remainder = tokens.suffix(from: tokens.index(after: remoteIndex))
        var endpoint: URL?
        var headers: [MCPHeader] = []
        var index = remainder.startIndex

        while index < remainder.endIndex {
            let token = remainder[index]
            let lower = token.lowercased()

            if lower == "--header" || lower == "-h" {
                let next = remainder.index(after: index)
                guard next < remainder.endIndex, let header = parseHeader(remainder[next]) else {
                    return nil
                }
                headers.append(header)
                index = remainder.index(after: next)
                continue
            }

            if lower.hasPrefix("-") {
                if takesValue(flag: lower) {
                    let next = remainder.index(after: index)
                    if next < remainder.endIndex {
                        index = remainder.index(after: next)
                        continue
                    }
                }
                index = remainder.index(after: index)
                continue
            }

            if endpoint == nil, let url = parseEndpoint(token) {
                endpoint = url
                index = remainder.index(after: index)
                continue
            }

            index = remainder.index(after: index)
        }

        guard let endpoint else { return nil }
        return MCPRemoteProxyCommand(endpoint: endpoint, headers: headers)
    }

    static func isMCPRemotePackage(_ token: String) -> Bool {
        let base = (token as NSString).lastPathComponent.lowercased()
        return base == "mcp-remote" || base.hasPrefix("mcp-remote@")
    }

    private static func parseEndpoint(_ token: String) -> URL? {
        guard let trimmed = token.trimmedNonEmpty,
              let url = URL(string: trimmed),
              url.scheme != nil else {
            return nil
        }
        return url
    }

    private static func parseHeader(_ raw: String) -> MCPHeader? {
        let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let name = String(parts[0]).trimmedNonEmpty else {
            return nil
        }
        let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return MCPHeader(
            name: name,
            value: value,
            isSensitive: MCPHTTPTransportConfig.isSensitiveHeaderName(name)
        )
    }

    private static func takesValue(flag: String) -> Bool {
        [
            "--transport",
            "--static-oauth-client-info",
            "--static-oauth-client-metadata",
            "--static-oauth-client-id",
            "--resource"
        ].contains(flag)
    }
}
