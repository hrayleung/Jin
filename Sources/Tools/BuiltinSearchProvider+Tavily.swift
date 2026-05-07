import Foundation

extension BuiltinSearchToolHub {
    func searchTavily(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        var request = URLRequest(url: try validatedURL("https://api.tavily.com/search"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let clampedMax = args.maxResults.clamped(to: 0...20)

        var body: [String: Any] = [
            "query": args.query,
            "max_results": clampedMax
        ]

        let searchDepth = tavilySearchDepthValue(
            normalizedTrimmedString(route.overrides?.tavilySearchDepth)
                ?? route.settings.tavilySearchDepth
        )
        body["search_depth"] = searchDepth

        let topic = tavilyTopicValue(
            normalizedTrimmedString(route.overrides?.tavilyTopic)
                ?? route.settings.tavilyTopic
        )
        body["topic"] = topic

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
            body["exclude_domains"] = Array(args.excludeDomains.prefix(150))
        }

        if args.includeRawContent {
            body["include_raw_content"] = "markdown"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await networkManager.sendRequest(request)
        let json = try parseJSONObject(data)

        let rows = parseArray(json["results"]).prefix(clampedMax).compactMap { item -> SearchCitationRow? in
            guard let url = firstString(in: item, keys: ["url"]) else { return nil }
            let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
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
}
