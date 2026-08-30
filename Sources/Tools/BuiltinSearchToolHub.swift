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
            if let key = settings.apiKey(for: explicitProvider).trimmedNonEmpty {
                resolvedProvider = explicitProvider
                resolvedAPIKey = key
            }
        } else {
            let providerCandidates = [settings.defaultProvider] + SearchPluginProvider.allCases
            for candidate in providerCandidates {
                if let key = settings.apiKey(for: candidate).trimmedNonEmpty {
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
            description: "Web search. Returns title, url, snippet, and optional publish time.",
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
        case .tinyfish:
            output = try await searchTinyFish(resolved, route: route)
        case .parallel:
            output = try await searchParallel(resolved, route: route)
        }

        let text = prettyJSONString(from: output)
            ?? prettyJSONString(from: BuiltinSearchToolOutput.empty(provider: route.provider, query: resolved.query))
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
        let objective: String?
        let searchQueries: [String]
    }

    private func resolveArguments(_ arguments: [String: AnyCodable], route: ToolRoute) throws -> ResolvedArguments {
        let raw = arguments.mapValues { $0.value }

        guard let query = firstString(
            in: raw,
            keys: ["query", "q", "input", "text"]
        ) else {
            throw LLMError.invalidRequest(message: "Builtin web search tool requires a non-empty `query`.")
        }

        let defaultMaxResults = route.overrides?.maxResults ?? route.settings.defaultMaxResults
        let requestedMaxResults = firstInt(in: raw, keys: ["max_results", "maxResults", "results", "limit", "count"]) ?? defaultMaxResults
        let maxResults = max(0, requestedMaxResults)

        let defaultRecency = route.overrides?.recencyDays ?? route.settings.defaultRecencyDays
        let rawRecencyDays = firstInt(in: raw, keys: ["recency_days", "recencyDays"])
            ?? defaultRecency
        let recencyDays = rawRecencyDays.flatMap { value in
            value == 0 ? nil : value.clamped(to: 1...365)
        }

        let includeRaw = firstBool(in: raw, keys: ["include_raw_content", "includeRawContent"])
            ?? route.overrides?.includeRawContent
            ?? false
        let fetchPages = firstBool(in: raw, keys: ["fetch_page_content", "fetchPageContent"])
            ?? route.overrides?.fetchPageContent
            ?? defaultFetchPageContent(for: route)

        let includeDomains = firstStringArray(in: raw, keys: ["include_domains", "includeDomains"])
        let excludeDomains = firstStringArray(in: raw, keys: ["exclude_domains", "excludeDomains"])
        let objective = firstString(in: raw, keys: ["objective"])
        let searchQueries = firstStringArray(in: raw, keys: ["search_queries", "searchQueries"])

        return ResolvedArguments(
            query: query,
            maxResults: maxResults,
            recencyDays: recencyDays,
            includeRawContent: includeRaw,
            fetchPageContent: fetchPages,
            includeDomains: includeDomains,
            excludeDomains: excludeDomains,
            objective: objective,
            searchQueries: searchQueries
        )
    }

    private func defaultFetchPageContent(for route: ToolRoute) -> Bool {
        switch route.provider {
        case .jina:
            return route.settings.jinaReadPages
        case .tinyfish:
            return route.settings.tinyfishFetchPages
        case .parallel:
            return route.settings.parallelExtractPages
        case .exa, .brave, .firecrawl, .tavily, .perplexity:
            return false
        }
    }

    private static let defaultParameterSchema = ParameterSchema(
        properties: [
            "query": PropertySchema(type: "string", description: "Search query."),
            "objective": PropertySchema(
                type: "string",
                description: "Natural-language search goal. Used by Parallel together with search_queries."
            ),
            "search_queries": PropertySchema(
                type: "array",
                description: "1-5 keyword queries of 3-6 words each. Used by Parallel. Do not use site: operators.",
                items: PropertySchema(type: "string")
            ),
            "max_results": PropertySchema(
                type: "integer",
                description: "Max results (provider limits apply)."
            ),
            "recency_days": PropertySchema(type: "integer", description: "Prefer results from the last N days."),
            "include_domains": PropertySchema(
                type: "array",
                description: "Optional domain allowlist.",
                items: PropertySchema(type: "string")
            ),
            "exclude_domains": PropertySchema(
                type: "array",
                description: "Optional domain blocklist.",
                items: PropertySchema(type: "string")
            ),
            "include_raw_content": PropertySchema(type: "boolean", description: "Include extra page snippets when supported."),
            "fetch_page_content": PropertySchema(
                type: "boolean",
                description: "Fetch result pages for richer snippets (Jina, TinyFish, Parallel Extract)."
            )
        ],
        required: ["query"]
    )
}

struct BuiltinSearchToolOutput: Codable, Sendable {
    let provider: SearchPluginProvider
    let query: String
    let resultCount: Int
    let results: [SearchCitationRow]

    static func empty(provider: SearchPluginProvider, query: String) -> Self {
        Self(provider: provider, query: query, resultCount: 0, results: [])
    }
}

struct SearchCitationRow: Codable, Sendable {
    let title: String
    let url: String
    let snippet: String?
    let publishedAt: String?
    let source: String?
}
