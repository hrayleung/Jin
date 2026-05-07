import Foundation

// MARK: - Individual Provider Execution

extension BuiltinSearchToolHub {
    // MARK: - Exa

    func searchExa(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        var request = URLRequest(url: try validatedURL("https://api.exa.ai/search"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let maxResults = args.maxResults.clamped(to: 1...50)
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
}
