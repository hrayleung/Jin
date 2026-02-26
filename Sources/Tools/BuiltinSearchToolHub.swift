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
    private let networkManager = NetworkManager()

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

    private struct ResolvedArguments: Sendable {
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

    // MARK: - Exa

    private func searchExa(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        var request = URLRequest(url: try validatedURL("https://api.exa.ai/search"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let maxResults = clamp(args.maxResults, min: 1, max: 50)
        var body: [String: Any] = [
            "query": args.query,
            "numResults": maxResults
        ]

        if let searchType = route.overrides?.exaSearchType ?? route.settings.exaSearchType {
            body["type"] = searchType.rawValue
        }
        if !args.includeDomains.isEmpty {
            body["includeDomains"] = args.includeDomains
        }
        if !args.excludeDomains.isEmpty {
            body["excludeDomains"] = args.excludeDomains
        }
        if let recencyDays = args.recencyDays {
            let start = Date(timeIntervalSinceNow: TimeInterval(-recencyDays * 86_400))
            body["startPublishedDate"] = Self.iso8601String(start)
        }
        if args.includeRawContent {
            // Exa API requires content retrieval to be nested under "contents"
            body["contents"] = ["text": true]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await networkManager.sendRequest(request)
        let json = try parseJSONObject(data)

        let results = parseArray(json["results"]).prefix(maxResults).compactMap { item -> SearchCitationRow? in
            guard let url = firstString(in: item, keys: ["url", "id"]) else { return nil }
            let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
            let firstHighlight = highlights(from: item["highlights"])
            let snippet = firstString(in: item, keys: ["text", "summary", "snippet", "highlightsSummary"])
                ?? firstHighlight.flatMap { firstString(in: $0, keys: ["text", "highlight", "snippet"]) }
                ?? firstString(in: item, keys: ["contents"])
            let publishedAt = firstString(in: item, keys: ["publishedDate", "published_at", "date"])
            return SearchCitationRow(
                title: title,
                url: url,
                snippet: snippet,
                publishedAt: publishedAt,
                source: urlHost(url)
            )
        }

        return BuiltinSearchToolOutput(
            provider: .exa,
            query: args.query,
            resultCount: results.count,
            results: results
        )
    }

    // MARK: - Brave

    private func searchBrave(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        let desiredMaxResults = max(1, args.maxResults)
        let requestCount = desiredMaxResults <= BraveSearchAPI.maxCount ? desiredMaxResults : BraveSearchAPI.maxCount
        let shouldIncludeExtraSnippets = args.includeRawContent

        let country = normalizedTrimmedString(route.overrides?.braveCountry) ?? route.settings.braveCountry
        let language = normalizedTrimmedString(route.overrides?.braveLanguage) ?? route.settings.braveLanguage
        let safesearch = normalizedTrimmedString(route.overrides?.braveSafesearch) ?? route.settings.braveSafesearch

        let freshness = args.recencyDays.map { braveFreshnessValue(recencyDays: $0) }
        let pageCount = Int(ceil(Double(desiredMaxResults) / Double(BraveSearchAPI.maxCount)))
        let maxPages = min(pageCount, BraveSearchAPI.maxOffset + 1)

        var seenURLs = Set<String>()
        var rows: [SearchCitationRow] = []
        rows.reserveCapacity(desiredMaxResults)

        for pageIndex in 0..<maxPages {
            guard rows.count < desiredMaxResults else { break }

            guard let url = BraveSearchAPI.makeWebSearchURL(
                query: args.query,
                count: requestCount,
                offset: pageIndex == 0 ? nil : pageIndex,
                freshness: freshness,
                country: country,
                searchLanguage: language,
                safesearch: safesearch,
                extraSnippets: shouldIncludeExtraSnippets
            ) else {
                throw LLMError.invalidRequest(message: "Failed to construct Brave search URL.")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue(route.apiKey, forHTTPHeaderField: "X-Subscription-Token")
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            let (data, _) = try await networkManager.sendRequest(request)
            let json = try parseJSONObject(data)

            let query = json["query"] as? [String: Any] ?? [:]
            let web = json["web"] as? [String: Any] ?? [:]
            let results = parseArray(web["results"])
            let moreResultsAvailable = firstBool(in: query, keys: ["more_results_available"])
            for item in results {
                guard rows.count < desiredMaxResults else { break }

                guard let url = firstString(in: item, keys: ["url", "profile", "link"]) else { continue }
                guard seenURLs.insert(url).inserted else { continue }

                let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
                let snippet = braveSnippet(from: item, includeExtraSnippets: shouldIncludeExtraSnippets)
                let publishedAt = firstString(in: item, keys: ["age", "page_age", "published"])

                rows.append(
                    SearchCitationRow(
                        title: title,
                        url: url,
                        snippet: snippet,
                        publishedAt: publishedAt,
                        source: urlHost(url)
                    )
                )
            }

            if moreResultsAvailable == false || (moreResultsAvailable == nil && results.isEmpty) {
                break
            }
        }

        return BuiltinSearchToolOutput(provider: .brave, query: args.query, resultCount: rows.count, results: rows)
    }

    // MARK: - Jina

    private func searchJina(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        // Jina Search API: GET https://s.jina.ai/<encoded-query>
        let encoded = args.query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? args.query
        var components = URLComponents(string: "https://s.jina.ai/\(encoded)")
        let queryItems: [URLQueryItem] = args.includeDomains.map { domain in
            URLQueryItem(name: "site", value: domain)
        }
        let resolvedMaxResults = min(max(args.maxResults, 1), 5)
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw LLMError.invalidRequest(message: "Failed to construct Jina search URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await networkManager.sendRequest(request)
        let response = try parseJSON(data)

        var rawResults: [[String: Any]]
        switch response {
        case let results as [[String: Any]]:
            rawResults = results
        case let results as [Any]:
            rawResults = parseArray(results)
        case let dict as [String: Any]:
            rawResults = parseArray(dict["data"])
            if rawResults.isEmpty {
                rawResults = parseArray(dict["web"])
            }
            if rawResults.isEmpty {
                rawResults = parseArray(dict["results"])
            }
        default:
            throw LLMError.decodingError(message: "Unexpected Jina response format.")
        }

        var rows = rawResults.prefix(resolvedMaxResults).compactMap { item -> SearchCitationRow? in
            guard let url = firstString(in: item, keys: ["url", "link"]) else { return nil }
            let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
            let snippet = firstString(in: item, keys: ["snippet", "summary", "description", "text", "content"])
            let publishedAt = firstString(in: item, keys: ["publishedDate", "date", "published"])
            return SearchCitationRow(
                title: title,
                url: url,
                snippet: snippet,
                publishedAt: publishedAt,
                source: urlHost(url)
            )
        }

        if args.fetchPageContent {
            rows = try await enrichJinaRowsWithReader(rows)
        }

        return BuiltinSearchToolOutput(
            provider: .jina,
            query: args.query,
            resultCount: rows.count,
            results: rows
        )
    }

    private func enrichJinaRowsWithReader(_ rows: [SearchCitationRow]) async throws -> [SearchCitationRow] {
        var out: [SearchCitationRow] = []
        out.reserveCapacity(rows.count)

        for (index, row) in rows.enumerated() {
            guard index < 3 else {
                out.append(row)
                continue
            }
            if let snippet = try await fetchJinaReaderSnippet(for: row.url) {
                out.append(
                    SearchCitationRow(
                        title: row.title,
                        url: row.url,
                        snippet: snippet,
                        publishedAt: row.publishedAt,
                        source: row.source
                    )
                )
            } else {
                out.append(row)
            }
        }

        return out
    }

    private func fetchJinaReaderSnippet(for urlString: String) async throws -> String? {
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        let readerURL = try validatedURL("https://r.jina.ai/\(encoded)")
        var request = URLRequest(url: readerURL)
        request.httpMethod = "GET"
        let (data, _) = try await networkManager.sendRequest(request)
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let condensed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !condensed.isEmpty else { return nil }
        return String(condensed.prefix(500))
    }

    // MARK: - Firecrawl

    private func searchFirecrawl(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        var request = URLRequest(url: try validatedURL("https://api.firecrawl.dev/v2/search"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let maxResults = clamp(args.maxResults, min: 1, max: 50)
        var body: [String: Any] = [
            "query": args.query,
            "limit": maxResults
        ]

        if let recency = args.recencyDays {
            body["tbs"] = firecrawlRecencyValue(recencyDays: recency)
        }
        if let country = normalizedTrimmedString(route.overrides?.braveCountry) ?? route.settings.braveCountry {
            body["country"] = country
        }

        let shouldExtractContent = route.overrides?.firecrawlExtractContent ?? route.settings.firecrawlExtractContent
        if shouldExtractContent || args.includeRawContent {
            body["scrapeOptions"] = ["formats": ["markdown"]]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await networkManager.sendRequest(request)
        let json = try parseJSONObject(data)

        if let success = json["success"] as? Bool, !success {
            throw LLMError.invalidRequest(message: firecrawlErrorMessage(from: json))
        }

        var raw = parseArray(json["data"])
        if raw.isEmpty {
            raw = parseArray((json["data"] as? [String: Any])?["web"])
        }
        if raw.isEmpty {
            raw = parseArray((json["data"] as? [String: Any])?["results"])
        }
        if raw.isEmpty {
            raw = parseArray(json["results"])
        }

        let rows = raw.prefix(maxResults).compactMap { item -> SearchCitationRow? in
            guard let url = firstString(in: item, keys: ["url", "link"]) else { return nil }
            let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
            let snippet = firstString(in: item, keys: ["description", "markdown", "summary", "content", "snippet"])
            let publishedAt = firstString(in: item, keys: ["publishedDate", "published", "date"])
            return SearchCitationRow(
                title: title,
                url: url,
                snippet: snippet.map { String($0.prefix(500)) },
                publishedAt: publishedAt,
                source: urlHost(url)
            )
        }

        return BuiltinSearchToolOutput(
            provider: .firecrawl,
            query: args.query,
            resultCount: rows.count,
            results: rows
        )
    }

    // MARK: - Tavily

    private func searchTavily(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        var request = URLRequest(url: try validatedURL("https://api.tavily.com/search"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        // max_results: Tavily supports 0-20
        let clampedMax = clamp(args.maxResults, min: 0, max: 20)

        var body: [String: Any] = [
            "query": args.query,
            "max_results": clampedMax
        ]

        // Tavily supports "basic", "fast", "advanced", and "ultra-fast".
        let searchDepth = tavilySearchDepthValue(
            normalizedTrimmedString(route.overrides?.tavilySearchDepth)
                ?? route.settings.tavilySearchDepth
        )
        body["search_depth"] = searchDepth

        // topic: "general" | "news" | "finance"
        let topic = tavilyTopicValue(
            normalizedTrimmedString(route.overrides?.tavilyTopic)
                ?? route.settings.tavilyTopic
        )
        body["topic"] = topic

        // Prefer exact recency windows over bucketed time ranges.
        if let recency = args.recencyDays {
            if let startDate = Calendar.current.date(
                byAdding: .day,
                value: -recency,
                to: Date()
            ) {
                let date = tavilyDateFormatter.string(from: startDate)
                body["start_date"] = date
                body["end_date"] = tavilyDateFormatter.string(from: Date())
            } else {
                body["time_range"] = tavilyTimeRange(recencyDays: recency)
            }
        }

        if !args.includeDomains.isEmpty {
            body["include_domains"] = Array(args.includeDomains.prefix(300))
        }
        if !args.excludeDomains.isEmpty {
            // Tavily excludes up to 150 domains (include_domains supports a larger limit).
            body["exclude_domains"] = Array(args.excludeDomains.prefix(150))
        }

        // include_raw_content: include cleaned markdown/snippets when requested
        if args.includeRawContent {
            body["include_raw_content"] = "markdown"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await networkManager.sendRequest(request)
        let json = try parseJSONObject(data)

        let rows = parseArray(json["results"]).prefix(clampedMax).compactMap { item -> SearchCitationRow? in
            guard let url = firstString(in: item, keys: ["url"]) else { return nil }
            let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
            // "content" is the primary snippet; "raw_content" is full page text when requested
            let snippet = firstString(
                in: item,
                keys: ["raw_content", "content", "text", "snippet", "summary"]
            )
            return SearchCitationRow(
                title: title,
                url: url,
                snippet: snippet.map { String($0.prefix(500)) },
                publishedAt: firstString(in: item, keys: ["published_date", "publishedDate", "published_at", "published"]),
                source: urlHost(url)
            )
        }

        return BuiltinSearchToolOutput(
            provider: .tavily,
            query: args.query,
            resultCount: rows.count,
            results: rows
        )
    }

    // MARK: - Helpers

    private func parseJSON(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }

    private func parseJSONObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decodingError(message: "Expected JSON object response.")
        }
        return object
    }

    private func parseArray(_ value: Any?) -> [[String: Any]] {
        if let array = value as? [[String: Any]] {
            return array
        }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private func stringValues(_ value: Any?) -> [String] {
        if let values = value as? [String] {
            return values.compactMap { normalizedTrimmedString($0) }
        }
        if let values = value as? [Any] {
            return values.compactMap { item in
                if let value = item as? String {
                    return normalizedTrimmedString(value)
                }
                if let value = item as? [String: Any],
                   let text = firstString(in: value, keys: ["text", "message", "detail"]) {
                    return text
                }
                return nil
            }
        }
        return []
    }

    private func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func firstInt(in dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }
            if let value = dictionary[key] as? Double {
                return Int(value.rounded())
            }
            if let value = dictionary[key] as? String,
               let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return intValue
            }
        }
        return nil
    }

    private func firstBool(in dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }
            if let value = dictionary[key] as? String {
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "1", "yes", "on":
                    return true
                case "false", "0", "no", "off":
                    return false
                default:
                    continue
                }
            }
        }
        return nil
    }

    private func firecrawlErrorMessage(from json: [String: Any]) -> String {
        if let errors = firstString(in: json, keys: ["error", "message", "status"])?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !errors.isEmpty {
            return errors
        }

        let flattenedErrors = stringValues(json["errors"])
        if let first = flattenedErrors.first {
            return first
        }

        if let details = firstString(in: json, keys: ["details"]),
           !details.isEmpty {
            return details
        }

        return "Unknown Firecrawl error."
    }

    private func highlights(from value: Any?) -> [String: Any]? {
        if let values = value as? [String] {
            return values.isEmpty ? nil : ["text": values[0]]
        }
        if let value = value as? [[String: Any]], let first = value.first {
            return first
        }
        return value as? [String: Any]
    }

    private func firstStringArray(in dictionary: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            if let value = dictionary[key] as? [String] {
                return value.compactMap { normalizedTrimmedString($0) }
            }
            if let value = dictionary[key] as? [Any] {
                return value.compactMap { item in
                    normalizedTrimmedString(item as? String)
                }
            }
        }
        return []
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func prettyJSONString<T: Encodable>(from value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func braveFreshnessValue(recencyDays: Int) -> String {
        switch recencyDays {
        case ...1:
            return "pd"
        case ...7:
            return "pw"
        case ...31:
            return "pm"
        default:
            return "py"
        }
    }

    private func tavilyTimeRange(recencyDays: Int) -> String {
        switch recencyDays {
        case ...1:
            return "day"
        case ...7:
            return "week"
        case ...31:
            return "month"
        default:
            return "year"
        }
    }

    private var tavilyDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func tavilySearchDepthValue(_ value: String?) -> String {
        guard let depth = normalizedTrimmedString(value)?.lowercased() else {
            return "basic"
        }
        let normalized = depth.replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "basic", "fast", "advanced", "ultra_fast":
            return normalized == "ultra_fast" ? "ultra-fast" : normalized
        default:
            return "basic"
        }
    }

    private func tavilyTopicValue(_ value: String?) -> String {
        guard let topic = normalizedTrimmedString(value)?.lowercased() else { return "general" }
        switch topic {
        case "general", "news", "finance":
            return topic
        default:
            return "general"
        }
    }

    private func firecrawlRecencyValue(recencyDays: Int) -> String {
        switch recencyDays {
        case ...1:
            return "qdr:d"
        case ...7:
            return "qdr:w"
        case ...31:
            return "qdr:m"
        default:
            return "qdr:y"
        }
    }

    private func urlHost(_ urlString: String) -> String? {
        URL(string: urlString)?.host
    }

    private func clamp(_ value: Int, min minimum: Int, max maximum: Int) -> Int {
        Swift.max(minimum, Swift.min(maximum, value))
    }

    private func braveSnippet(from item: [String: Any], includeExtraSnippets: Bool) -> String? {
        var parts: [String] = []
        var seenParts = Set<String>()

        for value in [
            firstString(in: item, keys: ["description"]),
            firstString(in: item, keys: ["snippet"])
        ].compactMap({ $0 }) {
            if seenParts.insert(value).inserted {
                parts.append(value)
            }
        }

        if includeExtraSnippets {
            let extras = firstStringArray(in: item, keys: ["extra_snippets"])
            for extra in extras where seenParts.insert(extra).inserted {
                parts.append(extra)
            }
        }

        let joined = parts
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(500))
    }
}

private struct BuiltinSearchToolOutput: Codable, Sendable {
    let provider: SearchPluginProvider
    let query: String
    let resultCount: Int
    let results: [SearchCitationRow]
}

private struct SearchCitationRow: Codable, Sendable {
    let title: String
    let url: String
    let snippet: String?
    let publishedAt: String?
    let source: String?
}
