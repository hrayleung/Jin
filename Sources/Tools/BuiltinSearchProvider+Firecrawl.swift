import Foundation

extension BuiltinSearchToolHub {
    func searchFirecrawl(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        var request = URLRequest(url: try validatedURL("https://api.firecrawl.dev/v2/search"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let body = Self.makeFirecrawlRequestBody(args: args, settings: route.settings, overrides: route.overrides)
        let maxResults = args.maxResults.clamped(to: 1...50)

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await networkManager.sendRequest(request)
        let json = try parseJSONObject(data)

        if let success = json["success"] as? Bool, !success {
            throw LLMError.invalidRequest(message: firecrawlErrorMessage(from: json))
        }

        var raw = parseArray(json["data"])
        let dataDict = json["data"] as? [String: Any]

        if raw.isEmpty {
            raw = parseArray(dataDict?["web"])
        }
        if let news = dataDict?["news"] {
            raw.append(contentsOf: parseArray(news))
        }
        if let images = dataDict?["images"] {
            raw.append(contentsOf: parseArray(images))
        }
        if raw.isEmpty {
            raw = parseArray(dataDict?["results"])
        }
        if raw.isEmpty {
            raw = parseArray(json["results"])
        }

        let rows = Self.makeFirecrawlRows(from: raw, maxResults: maxResults)

        return BuiltinSearchToolOutput(
            provider: .firecrawl,
            query: args.query,
            resultCount: rows.count,
            results: rows
        )
    }

    /// Pure builder for the `/v2/search` request body, exposed for tests.
    nonisolated static func makeFirecrawlRequestBody(
        args: ResolvedArguments,
        settings: WebSearchPluginSettings,
        overrides: SearchPluginControls?
    ) -> [String: Any] {
        let maxResults = args.maxResults.clamped(to: 1...50)
        let augmentedQuery = firecrawlAugmentedQuery(
            args.query,
            includeDomains: args.includeDomains,
            excludeDomains: args.excludeDomains
        )

        var body: [String: Any] = [
            "query": augmentedQuery,
            "limit": maxResults,
            "ignoreInvalidURLs": true
        ]

        if let recency = args.recencyDays {
            body["tbs"] = firecrawlRecencyTBS(recencyDays: recency)
        }

        if let country = (overrides?.firecrawlCountry?.trimmedNonEmpty ?? settings.firecrawlCountry?.trimmedNonEmpty) {
            body["country"] = country
        }

        if let language = settings.firecrawlLanguage?.trimmedNonEmpty {
            body["lang"] = language
        }

        if !settings.firecrawlSources.isEmpty {
            body["sources"] = settings.firecrawlSources.map { ["type": $0.rawValue] }
        }

        let shouldExtractContent = overrides?.firecrawlExtractContent ?? settings.firecrawlExtractContent
        if shouldExtractContent || args.includeRawContent {
            body["scrapeOptions"] = ["formats": ["markdown"]]
        }

        return body
    }

    /// Pure recency-window mapper duplicated as a `nonisolated static` so the body builder can
    /// remain test-callable without crossing actor isolation.
    nonisolated static func firecrawlRecencyTBS(recencyDays: Int) -> String {
        switch recencyDays {
        case ...1: return "qdr:d"
        case ...7: return "qdr:w"
        case ...31: return "qdr:m"
        default: return "qdr:y"
        }
    }

    /// Pure mapper for Firecrawl result rows. Dedupes by URL before applying the cap because
    /// multi-source responses can repeat the same hit across web, news, and image buckets.
    nonisolated static func makeFirecrawlRows(from raw: [[String: Any]], maxResults: Int) -> [SearchCitationRow] {
        let cap = maxResults.clamped(to: 0...50)
        guard cap > 0 else { return [] }

        var seenURLs = Set<String>()
        var rows: [SearchCitationRow] = []
        rows.reserveCapacity(min(cap, raw.count))

        for item in raw {
            guard rows.count < cap else { break }
            guard let url = firstFirecrawlString(in: item, keys: ["url", "link", "imageUrl"]) else { continue }
            guard seenURLs.insert(url).inserted else { continue }

            let title = firstFirecrawlString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
            let snippet = firstFirecrawlString(in: item, keys: ["description", "snippet", "markdown", "summary", "content"])
            let publishedAt = firstFirecrawlString(in: item, keys: ["publishedDate", "published", "date"])
            rows.append(SearchCitationRow(
                title: title,
                url: url,
                snippet: snippet.map { String($0.prefix(500)) },
                publishedAt: publishedAt,
                source: URL(string: url)?.host
            ))
        }

        return rows
    }

    private nonisolated static func firstFirecrawlString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String,
               let trimmed = value.trimmedNonEmpty {
                return trimmed
            }
        }
        return nil
    }
}
