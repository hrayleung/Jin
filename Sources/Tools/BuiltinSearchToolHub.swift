import Collections
import Foundation

struct BuiltinToolRouteSnapshot: Sendable {
    fileprivate let routes: [String: BuiltinSearchToolHub.ToolRoute]

    func contains(functionName: String) -> Bool {
        routes[functionName] != nil
    }

    func provider(for functionName: String) -> SearchPluginProvider? {
        routes[functionName]?.provider
    }
}

actor BuiltinSearchToolHub {
    static let shared = BuiltinSearchToolHub()

    static let serverID = "builtin_search"
    static let toolName = "web_lookup"
    static let functionName = MCPHub.makeFunctionName(serverID: serverID, toolName: toolName)
    static let functionNamePrefix = "\(serverID)__"

    static func isBuiltinSearchFunctionName(_ functionName: String) -> Bool {
        functionName.hasPrefix(functionNamePrefix)
    }

    private static let defaultToolName = functionName
    let networkManager = NetworkManager()

    func toolDefinitions(
        for controls: GenerationControls,
        useBuiltinSearch: Bool,
        defaults: UserDefaults = .standard
    ) -> (definitions: [ToolDefinition], routes: BuiltinToolRouteSnapshot) {
        guard useBuiltinSearch else { return ([], BuiltinToolRouteSnapshot(routes: [:])) }
        guard controls.webSearch?.enabled == true else { return ([], BuiltinToolRouteSnapshot(routes: [:])) }

        let settings = WebSearchPluginSettingsStore.load(defaults: defaults)
        guard settings.isEnabled else { return ([], BuiltinToolRouteSnapshot(routes: [:])) }

        var resolvedProvider: SearchPluginProvider?
        var resolvedAPIKey: String = ""
        if let explicitProvider = controls.searchPlugin?.provider {
            let key = settings.apiKey(for: explicitProvider).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                resolvedProvider = explicitProvider
                resolvedAPIKey = key
            }
        } else {
            let providerCandidates = [settings.defaultProvider] + SearchPluginProvider.allCases
            for candidate in providerCandidates {
                let key = settings.apiKey(for: candidate).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    resolvedProvider = candidate
                    resolvedAPIKey = key
                    break
                }
            }
        }
        guard let provider = resolvedProvider else {
            return ([], BuiltinToolRouteSnapshot(routes: [:]))
        }

        let route = ToolRoute(
            provider: provider,
            apiKey: resolvedAPIKey,
            settings: settings,
            overrides: controls.searchPlugin
        )

        let definition = ToolDefinition(
            id: "builtin:\(provider.rawValue):web_lookup",
            name: Self.defaultToolName,
            description: "Search the web and return structured citations with title, url, snippet, and optional publish time.",
            parameters: Self.defaultParameterSchema,
            source: .builtin
        )

        return ([definition], BuiltinToolRouteSnapshot(routes: [Self.defaultToolName: route]))
    }

    func executeTool(
        functionName: String,
        arguments: [String: AnyCodable],
        routes: BuiltinToolRouteSnapshot
    ) async throws -> MCPToolCallResult {
        guard let route = routes.routes[functionName] else {
            throw LLMError.invalidRequest(message: "Unknown builtin tool: \(functionName)")
        }

        let resolved = try resolveArguments(arguments, route: route)
        let output: BuiltinSearchToolOutput
        switch route.provider {
        case .exa:
            output = try await searchExa(resolved, route: route)
        case .brave:
            output = try await searchBrave(resolved, route: route)
        case .jina:
            output = try await searchJina(resolved, route: route)
        case .firecrawl:
            output = try await searchFirecrawl(resolved, route: route)
        case .tavily:
            output = try await searchTavily(resolved, route: route)
        case .perplexity:
            output = try await searchPerplexity(resolved, route: route)
        }

        let text = prettyJSONString(from: output)
            ?? prettyJSONString(
                from: BuiltinSearchToolOutput(
                    provider: route.provider,
                    query: resolved.query,
                    resultCount: 0,
                    results: []
                )
            )
            ?? #"{"provider":"exa","query":"","resultCount":0,"results":[]}"#
        return MCPToolCallResult(text: text, isError: false)
    }

    // MARK: - Route / Args

    struct ToolRoute: Sendable {
        let provider: SearchPluginProvider
        let apiKey: String
        let settings: WebSearchPluginSettings
        let overrides: SearchPluginControls?
    }

    struct ResolvedArguments: Sendable {
        let query: String
        let maxResults: Int
        let recencyDays: Int?
        let includeRawContent: Bool
        let fetchPageContent: Bool
        let includeDomains: [String]
        let excludeDomains: [String]
    }

    private func resolveArguments(_ arguments: [String: AnyCodable], route: ToolRoute) throws -> ResolvedArguments {
        let raw = arguments.mapValues { $0.value }

        let query = firstString(
            in: raw,
            keys: ["query", "q", "input", "text"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            throw LLMError.invalidRequest(message: "Builtin web search tool requires a non-empty `query`.")
        }

        let defaultMaxResults = route.overrides?.maxResults ?? route.settings.defaultMaxResults
        let requestedMaxResults = firstInt(in: raw, keys: ["max_results", "maxResults", "results", "limit", "count"]) ?? defaultMaxResults
        let maxResults = max(0, requestedMaxResults)

        let defaultRecency = route.overrides?.recencyDays ?? route.settings.defaultRecencyDays
        let rawRecencyDays = firstInt(in: raw, keys: ["recency_days", "recencyDays"])
            ?? defaultRecency
        let recencyDays = rawRecencyDays.flatMap { value in
            value == 0 ? nil : clamp(value, min: 1, max: 365)
        }

        let includeRaw = firstBool(in: raw, keys: ["include_raw_content", "includeRawContent"])
            ?? route.overrides?.includeRawContent
            ?? false
        let fetchPages = firstBool(in: raw, keys: ["fetch_page_content", "fetchPageContent"])
            ?? route.overrides?.fetchPageContent
            ?? route.settings.jinaReadPages

        let includeDomains = firstStringArray(in: raw, keys: ["include_domains", "includeDomains"])
        let excludeDomains = firstStringArray(in: raw, keys: ["exclude_domains", "excludeDomains"])

        return ResolvedArguments(
            query: query,
            maxResults: maxResults,
            recencyDays: recencyDays.map { clamp($0, min: 1, max: 365) },
            includeRawContent: includeRaw,
            fetchPageContent: fetchPages,
            includeDomains: includeDomains,
            excludeDomains: excludeDomains
        )
    }

    private static let defaultParameterSchema = ParameterSchema(
        properties: [
            "query": PropertySchema(type: "string", description: "What to search for."),
            "max_results": PropertySchema(
                type: "integer",
                description: "Maximum number of results to return (provider-specific limits apply, e.g. Tavily 0-20)."
            ),
            "recency_days": PropertySchema(type: "integer", description: "Prefer results from the last N days."),
            "include_domains": PropertySchema(
                type: "array",
                description: "Optional allowlist of domains.",
                items: PropertySchema(type: "string")
            ),
            "exclude_domains": PropertySchema(
                type: "array",
                description: "Optional blocklist of domains.",
                items: PropertySchema(type: "string")
            ),
            "include_raw_content": PropertySchema(type: "boolean", description: "Include extra raw page content/snippets when supported."),
            "fetch_page_content": PropertySchema(type: "boolean", description: "For Jina: fetch each result page via Reader for richer snippets.")
        ],
        required: ["query"]
    )
}

struct BuiltinSearchToolOutput: Codable, Sendable {
    let provider: SearchPluginProvider
    let query: String
    let resultCount: Int
    let results: [SearchCitationRow]
}

struct SearchCitationRow: Codable, Sendable {
    let title: String
    let url: String
    let snippet: String?
    let publishedAt: String?
    let source: String?
}
