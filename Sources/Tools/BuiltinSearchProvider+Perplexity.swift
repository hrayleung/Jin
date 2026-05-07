import Foundation

extension BuiltinSearchToolHub {
    func searchPerplexity(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        if args.maxResults == 0 {
            return BuiltinSearchToolOutput(
                provider: .perplexity,
                query: args.query,
                resultCount: 0,
                results: []
            )
        }

        var request = URLRequest(url: try validatedURL("https://api.perplexity.ai/search"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let clampedMax = args.maxResults.clamped(to: 1...20)
        var body: [String: Any] = [
            "query": args.query,
            "max_results": clampedMax
        ]

        if let recencyDays = args.recencyDays {
            body["search_recency_filter"] = perplexityRecencyFilter(recencyDays: recencyDays)
        }

        if !args.includeDomains.isEmpty && !args.excludeDomains.isEmpty {
            throw LLMError.invalidRequest(
                message: "Perplexity supports either `include_domains` or `exclude_domains`, not both."
            )
        }

        let domainFilter = perplexitySearchDomainFilter(
            includeDomains: args.includeDomains,
            excludeDomains: args.excludeDomains
        )
        if !domainFilter.isEmpty {
            body["search_domain_filter"] = domainFilter
        }

        if args.includeRawContent {
            body["max_tokens_per_page"] = 4_096
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await networkManager.sendRequest(request)
        let json = try parseJSONObject(data)

        let rows = parseArray(json["results"]).prefix(clampedMax).compactMap { item -> SearchCitationRow? in
            guard let url = firstString(in: item, keys: ["url", "link"]) else { return nil }
            let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
            let snippet = firstString(in: item, keys: ["snippet", "content", "text", "summary"])
            let publishedAt = firstString(
                in: item,
                keys: ["date", "last_updated", "published_date", "publishedDate", "published_at", "published"]
            )
            return SearchCitationRow(
                title: title,
                url: url,
                snippet: snippet.map { String($0.prefix(500)) },
                publishedAt: publishedAt,
                source: urlHost(url)
            )
        }

        return BuiltinSearchToolOutput(
            provider: .perplexity,
            query: args.query,
            resultCount: rows.count,
            results: rows
        )
    }
}
