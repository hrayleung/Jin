import Foundation

extension BuiltinSearchToolHub {
    func searchJina(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        let request = try Self.makeJinaRequest(
            args: args,
            settings: route.settings,
            apiKey: route.apiKey
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let response = try parseJSON(data)

        let rawResults = Self.extractJinaResults(from: response)
        let resolvedMaxResults = min(max(args.maxResults, 1), 5)

        let rows = rawResults.prefix(resolvedMaxResults).compactMap { item -> SearchCitationRow? in
            guard let url = firstString(in: item, keys: ["url", "link"]) else { return nil }
            let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
            let snippet = firstString(in: item, keys: ["content", "snippet", "summary", "description", "text"])
            let publishedAt = firstString(in: item, keys: ["publishedDate", "date", "published"])
            return SearchCitationRow(
                title: title,
                url: url,
                snippet: snippet.map { String($0.prefix(500)) },
                publishedAt: publishedAt,
                source: urlHost(url)
            )
        }

        return BuiltinSearchToolOutput(
            provider: .jina,
            query: args.query,
            resultCount: rows.count,
            results: rows
        )
    }

    /// Pure builder for the s.jina.ai POST request, exposed for tests.
    nonisolated static func makeJinaRequest(
        args: ResolvedArguments,
        settings: WebSearchPluginSettings,
        apiKey: String
    ) throws -> URLRequest {
        guard let url = URL(string: "https://s.jina.ai/") else {
            throw LLMError.invalidRequest(message: "Failed to construct Jina search URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("browser", forHTTPHeaderField: "X-Engine")

        if !args.fetchPageContent {
            request.addValue("no-content", forHTTPHeaderField: "X-Respond-With")
        }

        if args.includeRawContent {
            request.addValue("true", forHTTPHeaderField: "X-With-Generated-Alt")
            request.addValue("true", forHTTPHeaderField: "X-With-Links-Summary")
        }

        let trimmedIncludes = args.includeDomains.compactMap { $0.trimmedNonEmpty }
        if let firstSite = trimmedIncludes.first {
            request.addValue(firstSite, forHTTPHeaderField: "X-Site")
        }

        if let locale = settings.jinaLocale?.trimmedNonEmpty {
            request.addValue(locale, forHTTPHeaderField: "X-Locale")
        }

        let augmentedQuery = jinaAugmentedQuery(args.query, includeDomains: Array(trimmedIncludes.dropFirst()))
        var body: [String: Any] = ["q": augmentedQuery]
        if let country = settings.jinaCountry?.trimmedNonEmpty {
            body["gl"] = country
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Appends `site:` operators for any include domains beyond the first (which the X-Site header
    /// covers). Jina supports a single X-Site header; spillover goes into the body's query string.
    nonisolated static func jinaAugmentedQuery(_ query: String, includeDomains: [String]) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let domains = includeDomains.compactMap { $0.trimmedNonEmpty }.prefix(10)
        guard !domains.isEmpty else { return trimmed }

        let operators = domains.map { "site:\($0)" }.joined(separator: " OR ")
        return trimmed.isEmpty ? operators : "\(trimmed) \(operators)"
    }

    nonisolated static func extractJinaResults(from response: Any) -> [[String: Any]] {
        switch response {
        case let results as [[String: Any]]:
            return results
        case let results as [Any]:
            return results.compactMap { $0 as? [String: Any] }
        case let dict as [String: Any]:
            for key in ["data", "web", "results"] {
                if let values = dict[key] as? [[String: Any]] {
                    return values
                }
                if let values = dict[key] as? [Any] {
                    return values.compactMap { $0 as? [String: Any] }
                }
            }
            return []
        default:
            return []
        }
    }
}
