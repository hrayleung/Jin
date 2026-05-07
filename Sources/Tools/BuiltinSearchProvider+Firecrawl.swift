import Foundation

extension BuiltinSearchToolHub {
    func searchFirecrawl(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        var request = URLRequest(url: try validatedURL("https://api.firecrawl.dev/v2/search"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let maxResults = args.maxResults.clamped(to: 1...50)
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
}
