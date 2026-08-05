import Collections
import Foundation

extension BuiltinSearchToolHub {
    func searchBrave(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        let country = normalizedTrimmedString(route.overrides?.braveCountry) ?? route.settings.braveCountry
        let language = normalizedTrimmedString(route.overrides?.braveLanguage) ?? route.settings.braveLanguage
        let safesearch = normalizedTrimmedString(route.overrides?.braveSafesearch) ?? route.settings.braveSafesearch
        let freshness = args.recencyDays.map { Self.braveDateRangeFreshness(recencyDays: $0) }

        // When the caller wants richer page content, use Brave's LLM Context endpoint
        // (pre-extracted, relevance-ranked snippets optimized for model grounding).
        if args.includeRawContent {
            if let llmRows = try await searchBraveLLMContext(
                args: args,
                route: route,
                country: country,
                language: language,
                safesearch: safesearch,
                freshness: freshness
            ), !llmRows.isEmpty {
                return BuiltinSearchToolOutput(
                    provider: .brave,
                    query: args.query,
                    resultCount: llmRows.count,
                    results: llmRows
                )
            }
            // Fall through to classic Web Search if LLM Context returns nothing usable.
        }

        return try await searchBraveWeb(
            args: args,
            route: route,
            country: country,
            language: language,
            safesearch: safesearch,
            freshness: freshness,
            includeExtraSnippets: args.includeRawContent
        )
    }

    private func searchBraveLLMContext(
        args: ResolvedArguments,
        route: ToolRoute,
        country: String?,
        language: String?,
        safesearch: String?,
        freshness: String?
    ) async throws -> [SearchCitationRow]? {
        let desiredMaxResults = max(1, args.maxResults)
        let count = desiredMaxResults.clamped(to: 1...BraveSearchAPI.llmContextMaxCount)

        guard let url = BraveSearchAPI.makeLLMContextURL(
            query: args.query,
            count: count,
            maximumNumberOfURLs: count,
            freshness: freshness,
            country: country,
            searchLanguage: language,
            safesearch: safesearch,
            enableSourceMetadata: true
        ) else {
            throw LLMError.invalidRequest(message: "Failed to construct Brave LLM Context URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(route.apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await networkManager.sendRequest(request)
        let json = try parseJSONObject(data)
        return Self.makeBraveLLMContextRows(from: json, maxResults: desiredMaxResults)
    }

    private func searchBraveWeb(
        args: ResolvedArguments,
        route: ToolRoute,
        country: String?,
        language: String?,
        safesearch: String?,
        freshness: String?,
        includeExtraSnippets: Bool
    ) async throws -> BuiltinSearchToolOutput {
        let desiredMaxResults = max(1, args.maxResults)
        let requestCount = desiredMaxResults <= BraveSearchAPI.maxCount ? desiredMaxResults : BraveSearchAPI.maxCount
        let pageCount = Int(ceil(Double(desiredMaxResults) / Double(BraveSearchAPI.maxCount)))
        let maxPages = min(pageCount, BraveSearchAPI.maxOffset + 1)

        var seenURLs = OrderedSet<String>()
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
                extraSnippets: includeExtraSnippets
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
                guard !seenURLs.contains(url) else { continue }
                seenURLs.append(url)

                let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
                let snippet = braveSnippet(from: item, includeExtraSnippets: includeExtraSnippets)
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

    /// Maps Brave LLM Context JSON into citation rows.
    /// Response shape (docs): `grounding.generic[]` with `url`/`title`/`snippets[]`,
    /// optional `sources` map keyed by URL for metadata enrichment.
    nonisolated static func makeBraveLLMContextRows(
        from json: [String: Any],
        maxResults: Int
    ) -> [SearchCitationRow] {
        let cap = max(0, maxResults)
        guard cap > 0 else { return [] }

        let grounding = json["grounding"] as? [String: Any] ?? [:]
        let sources = json["sources"] as? [String: Any] ?? [:]

        // Prefer documented buckets; also accept any array values under grounding for forward-compat.
        var items: [[String: Any]] = []
        let preferredKeys = ["generic", "web", "news", "map", "local"]
        for key in preferredKeys {
            if let bucket = grounding[key] as? [[String: Any]] {
                items.append(contentsOf: bucket)
            } else if let bucket = grounding[key] as? [Any] {
                items.append(contentsOf: bucket.compactMap { $0 as? [String: Any] })
            }
        }
        if items.isEmpty {
            for (_, value) in grounding {
                if let bucket = value as? [[String: Any]] {
                    items.append(contentsOf: bucket)
                } else if let bucket = value as? [Any] {
                    items.append(contentsOf: bucket.compactMap { $0 as? [String: Any] })
                }
            }
        }

        var seenURLs = Set<String>()
        var rows: [SearchCitationRow] = []
        rows.reserveCapacity(min(cap, items.count))

        for item in items {
            guard rows.count < cap else { break }
            guard let url = firstString(in: item, keys: ["url", "link"]) else { continue }
            guard seenURLs.insert(url).inserted else { continue }

            let sourceMeta = sources[url] as? [String: Any]
            let title = firstString(in: item, keys: ["title"])
                ?? firstString(in: sourceMeta ?? [:], keys: ["title", "site_name"])
                ?? URL(string: url)?.host
                ?? url

            let snippet = braveLLMContextSnippet(from: item, sourceMeta: sourceMeta)
            let publishedAt = braveLLMContextPublishedAt(from: sourceMeta)
            let source = firstString(in: sourceMeta ?? [:], keys: ["hostname"])
                ?? URL(string: url)?.host

            rows.append(
                SearchCitationRow(
                    title: title,
                    url: url,
                    snippet: snippet,
                    publishedAt: publishedAt,
                    source: source
                )
            )
        }

        return rows
    }

    nonisolated private static func braveLLMContextSnippet(
        from item: [String: Any],
        sourceMeta: [String: Any]?
    ) -> String? {
        var parts = OrderedSet<String>()

        if let snippets = item["snippets"] as? [String] {
            for snippet in snippets {
                if let trimmed = snippet.trimmedNonEmpty {
                    parts.append(trimmed)
                }
            }
        } else if let snippets = item["snippets"] as? [Any] {
            for snippet in snippets {
                if let text = snippet as? String, let trimmed = text.trimmedNonEmpty {
                    parts.append(trimmed)
                }
            }
        }

        for key in ["snippet", "text", "content", "description"] {
            if let value = item[key] as? String, let trimmed = value.trimmedNonEmpty {
                parts.append(trimmed)
            }
        }

        if parts.isEmpty, let description = firstString(in: sourceMeta ?? [:], keys: ["description"]) {
            parts.append(description)
        }

        guard let joined = parts.elements.joined(separator: "\n").trimmedNonEmpty else { return nil }
        return String(joined.prefix(500))
    }

    nonisolated private static func braveLLMContextPublishedAt(from sourceMeta: [String: Any]?) -> String? {
        guard let sourceMeta else { return nil }
        if let age = sourceMeta["age"] as? [String] {
            // Prefer ISO-looking middle entry when Brave returns [display, ISO, relative].
            if age.count >= 2, age[1].contains("-") {
                return age[1].trimmedNonEmpty
            }
            return age.first?.trimmedNonEmpty
        }
        if let age = sourceMeta["age"] as? String {
            return age.trimmedNonEmpty
        }
        return firstString(in: sourceMeta, keys: ["published", "page_age", "date"])
    }

    /// Builds a UTC `YYYY-MM-DDtoYYYY-MM-DD` window for Brave's `freshness` parameter — strictly
    /// more precise than the coarse `pd|pw|pm|py` buckets the API also accepts.
    nonisolated static func braveDateRangeFreshness(recencyDays: Int, now: Date = Date()) -> String {
        let calendar = utcGregorianCalendar()
        let clamped = max(1, recencyDays)
        let start = calendar.date(byAdding: .day, value: -clamped, to: now) ?? now
        return "\(utcDateString(start, format: "yyyy-MM-dd"))to\(utcDateString(now, format: "yyyy-MM-dd"))"
    }
}
