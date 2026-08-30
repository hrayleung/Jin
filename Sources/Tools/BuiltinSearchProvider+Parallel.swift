import Foundation

extension BuiltinSearchToolHub {
    /// Public Search modes currently cap results at 20.
    /// https://docs.parallel.ai/search/advanced-search-settings — verified 2026-08-30.
    static let parallelMaxResultsRange = 1...20
    static let parallelSearchQueryLimit = 5
    static let parallelSearchQueryMaxCharacters = 200
    static let parallelObjectiveMaxCharacters = 5_000
    static let parallelExtractURLLimit = 20
    static let parallelExcerptJoinLimit = 8_000
    static let parallelDomainFilterLimit = 200

    /// ISO 3166-1 alpha-2 codes Parallel documents for `advanced_settings.location`.
    static let parallelSupportedLocations: Set<String> = [
        "ar", "au", "at", "be", "br", "ca", "cl", "cn", "dk", "fi",
        "fr", "de", "gr", "hk", "in", "id", "it", "jp", "my", "mx",
        "nl", "nz", "no", "ph", "pl", "pt", "ru", "sa", "za", "kr",
        "es", "se", "ch", "tw", "tr", "gb", "us"
    ]

    func searchParallel(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        if args.maxResults == 0 {
            return .empty(provider: .parallel, query: args.query)
        }

        var request = URLRequest(url: try validatedURL("https://api.parallel.ai/v1/search"))
        request.httpMethod = "POST"
        request.addValue(route.apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let body = Self.makeParallelSearchRequestBody(
            args: args,
            settings: route.settings,
            overrides: route.overrides
        )
        let clampedMax = args.maxResults.clamped(to: Self.parallelMaxResultsRange)

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await networkManager.sendRequest(request)
        let json = try parseJSONObject(data)

        var rows = parseArray(json["results"]).prefix(clampedMax).compactMap { item -> SearchCitationRow? in
            Self.makeParallelCitationRow(from: item)
        }

        let sessionID = firstString(in: json, keys: ["session_id"])
        if args.fetchPageContent, !rows.isEmpty {
            rows = try await extractParallelPages(
                rows,
                query: args.query,
                sessionID: sessionID,
                apiKey: route.apiKey
            )
        }

        return BuiltinSearchToolOutput(
            provider: .parallel,
            query: args.query,
            resultCount: rows.count,
            results: rows
        )
    }

    private func extractParallelPages(
        _ rows: [SearchCitationRow],
        query: String,
        sessionID: String?,
        apiKey: String
    ) async throws -> [SearchCitationRow] {
        let urls = Array(rows.map(\.url).prefix(Self.parallelExtractURLLimit))
        guard !urls.isEmpty else { return rows }

        var request = URLRequest(url: try validatedURL("https://api.parallel.ai/v1/extract"))
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.makeParallelExtractRequestBody(
                urls: urls,
                query: query,
                sessionID: sessionID
            )
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let json = try parseJSONObject(data)
        return Self.mergeParallelExtractedContent(rows: rows, extractResults: parseArray(json["results"]))
    }

    /// Pure builder for `POST /v1/search`, exposed for tests.
    /// https://docs.parallel.ai/api-reference/search/search — verified 2026-08-30.
    nonisolated static func makeParallelSearchRequestBody(
        args: ResolvedArguments,
        settings: WebSearchPluginSettings,
        overrides: SearchPluginControls?
    ) -> [String: Any] {
        let clampedMax = args.maxResults.clamped(to: parallelMaxResultsRange)
        let queries = parallelSearchQueries(from: args)
        var body: [String: Any] = [
            "objective": parallelObjective(from: args),
            "search_queries": queries
        ]

        body["mode"] = parallelSearchMode(overrides: overrides, settings: settings).rawValue

        var advanced: [String: Any] = [
            "max_results": clampedMax
        ]

        if let location = parallelLocationValue(settings.parallelLocation) {
            advanced["location"] = location
        }

        if let sourcePolicy = parallelSourcePolicy(
            includeDomains: args.includeDomains,
            excludeDomains: args.excludeDomains,
            recencyDays: args.recencyDays
        ) {
            advanced["source_policy"] = sourcePolicy
        }

        body["advanced_settings"] = advanced
        return body
    }

    /// Pure builder for `POST /v1/extract`, exposed for tests.
    /// https://docs.parallel.ai/api-reference/extract/extract — verified 2026-08-30.
    nonisolated static func makeParallelExtractRequestBody(
        urls: [String],
        query: String,
        sessionID: String?
    ) -> [String: Any] {
        var body: [String: Any] = [
            "urls": Array(urls.prefix(parallelExtractURLLimit)),
            "objective": parallelObjective(from: query),
            "search_queries": parallelSearchQueries(from: query)
        ]
        if let sessionID = sessionID?.trimmedNonEmpty {
            body["session_id"] = String(sessionID.prefix(1_000))
        }
        return body
    }

    /// Jin defaults to `fast` for agent tool loops. Parallel's API default is `advanced`.
    /// https://docs.parallel.ai/search/modes — verified 2026-08-30.
    nonisolated static func parallelSearchMode(
        overrides: SearchPluginControls?,
        settings: WebSearchPluginSettings
    ) -> ParallelSearchMode {
        overrides?.parallelSearchMode ?? settings.parallelSearchMode ?? .fast
    }

    /// Keyword queries Parallel wants: 1-5 items, 3-6 words, ≤200 chars, no `site:`.
    nonisolated static func parallelSearchQueries(from args: ResolvedArguments) -> [String] {
        let provided = args.searchQueries
            .compactMap { $0.trimmedNonEmpty }
            .map { String($0.prefix(parallelSearchQueryMaxCharacters)) }
            .filter { !$0.isEmpty }
        if !provided.isEmpty {
            return Array(provided.prefix(parallelSearchQueryLimit))
        }
        return parallelSearchQueries(from: args.query)
    }

    nonisolated static func parallelSearchQueries(from query: String) -> [String] {
        let trimmed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(parallelSearchQueryMaxCharacters))
        guard !trimmed.isEmpty else { return ["web search"] }
        return [trimmed]
    }

    nonisolated static func parallelObjective(from args: ResolvedArguments) -> String {
        if let objective = args.objective?.trimmedNonEmpty {
            return String(objective.prefix(parallelObjectiveMaxCharacters))
        }
        return parallelObjective(from: args.query)
    }

    nonisolated static func parallelObjective(from query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let objective = trimmed.isEmpty
            ? "Find current, cited web information relevant to the user's request."
            : "Find current, cited web information about: \(trimmed)"
        return String(objective.prefix(parallelObjectiveMaxCharacters))
    }

    nonisolated static func parallelLocationValue(_ value: String?) -> String? {
        guard let raw = value?.trimmedNonEmpty else { return nil }
        let normalized = raw.lowercased()
        if normalized == "uk" {
            return "gb"
        }
        return parallelSupportedLocations.contains(normalized) ? normalized : nil
    }

    nonisolated static func parallelSourcePolicy(
        includeDomains: [String],
        excludeDomains: [String],
        recencyDays: Int?,
        now: Date = Date()
    ) -> [String: Any]? {
        var policy: [String: Any] = [:]

        let includes = includeDomains.compactMap { $0.trimmedNonEmpty }
        let excludes = excludeDomains.compactMap { $0.trimmedNonEmpty }
        let combinedLimit = parallelDomainFilterLimit
        if !includes.isEmpty {
            policy["include_domains"] = Array(includes.prefix(combinedLimit))
        }
        if !excludes.isEmpty {
            let remaining = max(0, combinedLimit - includes.count)
            if remaining > 0 {
                policy["exclude_domains"] = Array(excludes.prefix(remaining))
            }
        }

        if let recencyDays, recencyDays > 0 {
            let calendar = utcGregorianCalendar()
            let start = calendar.date(byAdding: .day, value: -recencyDays, to: now) ?? now
            policy["after_date"] = utcDateString(start, format: "yyyy-MM-dd")
        }

        return policy.isEmpty ? nil : policy
    }

    nonisolated static func makeParallelCitationRow(from item: [String: Any]) -> SearchCitationRow? {
        guard let url = firstString(in: item, keys: ["url"]) else { return nil }
        let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
        let snippet = parallelExcerptSnippet(from: item["excerpts"])
        let publishedAt = firstString(in: item, keys: ["publish_date", "published_date", "publishedDate"])
        return SearchCitationRow(
            title: title,
            url: url,
            snippet: snippet,
            publishedAt: publishedAt,
            source: URL(string: url)?.host
        )
    }

    nonisolated static func mergeParallelExtractedContent(
        rows: [SearchCitationRow],
        extractResults: [[String: Any]]
    ) -> [SearchCitationRow] {
        var contentByURL: [String: String] = [:]
        for item in extractResults {
            guard let url = firstString(in: item, keys: ["url"]) else { continue }
            if let snippet = parallelExcerptSnippet(from: item["excerpts"])
                ?? firstString(in: item, keys: ["full_content"]) {
                contentByURL[url] = snippet
            }
        }

        return rows.map { row in
            guard let content = contentByURL[row.url] else { return row }
            return SearchCitationRow(
                title: row.title,
                url: row.url,
                snippet: content,
                publishedAt: row.publishedAt,
                source: row.source
            )
        }
    }

    nonisolated static func parallelExcerptSnippet(from value: Any?) -> String? {
        let excerpts: [String]
        if let values = value as? [String] {
            excerpts = values.compactMap { $0.trimmedNonEmpty }
        } else if let values = value as? [Any] {
            excerpts = values.compactMap { ($0 as? String)?.trimmedNonEmpty }
        } else {
            excerpts = []
        }

        guard let joined = excerpts.joined(separator: "\n\n").trimmedNonEmpty else { return nil }
        return String(joined.prefix(parallelExcerptJoinLimit))
    }
}
