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
        let body = Self.makeExaRequestBody(args: args, settings: route.settings, overrides: route.overrides)

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

    /// Pure builder for the `/search` request body, exposed for tests.
    nonisolated static func makeExaRequestBody(
        args: ResolvedArguments,
        settings: WebSearchPluginSettings,
        overrides: SearchPluginControls?
    ) -> [String: Any] {
        let maxResults = args.maxResults.clamped(to: 1...50)
        var body: [String: Any] = [
            "query": args.query,
            "numResults": maxResults
        ]

        if let searchType = overrides?.exaSearchType ?? settings.exaSearchType {
            body["type"] = searchType.rawValue
        }

        let category = ExaCategory.resolved(from: overrides?.exaCategory ?? settings.exaCategory)
        if let category {
            body["category"] = category.rawValue
        }
        let usesEntityCategory = category == .company || category == .people

        if let userLocation = settings.exaUserLocation?.trimmedNonEmpty {
            body["userLocation"] = userLocation
        }

        if settings.exaModeration {
            body["moderation"] = true
        }

        let includeDomains = exaIncludeDomains(args.includeDomains, category: category)
        if !includeDomains.isEmpty {
            body["includeDomains"] = includeDomains
        }

        if !usesEntityCategory, !args.excludeDomains.isEmpty {
            body["excludeDomains"] = args.excludeDomains
        }

        if !usesEntityCategory, let recencyDays = args.recencyDays {
            let start = Date(timeIntervalSinceNow: TimeInterval(-recencyDays * 86_400))
            body["startPublishedDate"] = iso8601String(start)
        }

        if args.includeRawContent {
            let text: [String: Any] = [
                "maxCharacters": 8_000,
                "verbosity": "compact"
            ]
            var contents: [String: Any] = ["text": text]
            if let recencyDays = args.recencyDays {
                contents["maxAgeHours"] = recencyDays * 24
            }
            body["contents"] = contents
        }

        return body
    }

    nonisolated static func exaIncludeDomains(_ domains: [String], category: ExaCategory?) -> [String] {
        guard category == .people else { return domains }
        return domains.filter { domain in
            guard let normalized = domain.trimmedNonEmpty?.lowercased() else { return false }
            return normalized == "linkedin.com" || normalized.hasSuffix(".linkedin.com")
        }
    }
}
