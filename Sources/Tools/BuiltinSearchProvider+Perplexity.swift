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

        if !args.includeDomains.isEmpty && !args.excludeDomains.isEmpty {
            throw LLMError.invalidRequest(
                message: "Perplexity supports either `include_domains` or `exclude_domains`, not both."
            )
        }

        var request = URLRequest(url: try validatedURL("https://api.perplexity.ai/search"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let body = Self.makePerplexityRequestBody(args: args, settings: route.settings, overrides: route.overrides)
        let clampedMax = args.maxResults.clamped(to: 1...20)

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

    /// Pure builder for the `/search` request body, exposed for tests.
    nonisolated static func makePerplexityRequestBody(
        args: ResolvedArguments,
        settings: WebSearchPluginSettings,
        overrides: SearchPluginControls?
    ) -> [String: Any] {
        let clampedMax = args.maxResults.clamped(to: 1...20)
        var body: [String: Any] = [
            "query": args.query,
            "max_results": clampedMax
        ]

        if let recencyDays = args.recencyDays {
            body["search_after_date_filter"] = perplexityDateFilter(daysAgo: recencyDays)
        }

        let domainFilter = perplexityDomainFilter(
            includeDomains: args.includeDomains,
            excludeDomains: args.excludeDomains
        )
        if !domainFilter.isEmpty {
            body["search_domain_filter"] = domainFilter
        }

        if let country = settings.perplexityCountry?.trimmedNonEmpty {
            body["country"] = country
        }

        if let language = settings.perplexityLanguage?.trimmedNonEmpty {
            body["search_language_filter"] = [language]
        }

        if args.includeRawContent {
            body["max_tokens"] = 4_096
        }

        return body
    }

    /// Builds the Perplexity `MM/DD/YYYY` UTC date string for `now - daysAgo`.
    nonisolated static func perplexityDateFilter(daysAgo: Int, now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let target = calendar.date(byAdding: .day, value: -max(1, daysAgo), to: now) ?? now

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: target)
    }

    nonisolated static func perplexityDomainFilter(includeDomains: [String], excludeDomains: [String]) -> [String] {
        let include = includeDomains.compactMap { $0.trimmedNonEmpty }
        if !include.isEmpty {
            return Array(include.prefix(20))
        }
        let exclude = excludeDomains.compactMap { $0.trimmedNonEmpty }.map { "-\($0)" }
        return Array(exclude.prefix(20))
    }
}
