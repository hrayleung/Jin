import Collections
import Foundation

// MARK: - Individual Provider Execution

extension BuiltinSearchToolHub {
    // MARK: - Exa

    func searchExa(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        var request = URLRequest(url: try validatedURL("https://api.exa.ai/search"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let maxResults = clamp(args.maxResults, min: 1, max: 50)
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

    // MARK: - Brave

    func searchBrave(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        let desiredMaxResults = max(1, args.maxResults)
        let requestCount = desiredMaxResults <= BraveSearchAPI.maxCount ? desiredMaxResults : BraveSearchAPI.maxCount
        let shouldIncludeExtraSnippets = args.includeRawContent

        let country = normalizedTrimmedString(route.overrides?.braveCountry) ?? route.settings.braveCountry
        let language = normalizedTrimmedString(route.overrides?.braveLanguage) ?? route.settings.braveLanguage
        let safesearch = normalizedTrimmedString(route.overrides?.braveSafesearch) ?? route.settings.braveSafesearch

        let freshness = args.recencyDays.map { braveFreshnessValue(recencyDays: $0) }
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
                extraSnippets: shouldIncludeExtraSnippets
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
                let snippet = braveSnippet(from: item, includeExtraSnippets: shouldIncludeExtraSnippets)
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

    // MARK: - Jina

    func searchJina(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        // Jina Search API: GET https://s.jina.ai/<encoded-query>
        let encoded = args.query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? args.query
        var components = URLComponents(string: "https://s.jina.ai/\(encoded)")
        let queryItems: [URLQueryItem] = args.includeDomains.map { domain in
            URLQueryItem(name: "site", value: domain)
        }
        let resolvedMaxResults = min(max(args.maxResults, 1), 5)
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw LLMError.invalidRequest(message: "Failed to construct Jina search URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await networkManager.sendRequest(request)
        let response = try parseJSON(data)

        var rawResults: [[String: Any]]
        switch response {
        case let results as [[String: Any]]:
            rawResults = results
        case let results as [Any]:
            rawResults = parseArray(results)
        case let dict as [String: Any]:
            rawResults = parseArray(dict["data"])
            if rawResults.isEmpty {
                rawResults = parseArray(dict["web"])
            }
            if rawResults.isEmpty {
                rawResults = parseArray(dict["results"])
            }
        default:
            throw LLMError.decodingError(message: "Unexpected Jina response format.")
        }

        var rows = rawResults.prefix(resolvedMaxResults).compactMap { item -> SearchCitationRow? in
            guard let url = firstString(in: item, keys: ["url", "link"]) else { return nil }
            let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
            let snippet = firstString(in: item, keys: ["snippet", "summary", "description", "text", "content"])
            let publishedAt = firstString(in: item, keys: ["publishedDate", "date", "published"])
            return SearchCitationRow(
                title: title,
                url: url,
                snippet: snippet,
                publishedAt: publishedAt,
                source: urlHost(url)
            )
        }

        if args.fetchPageContent {
            rows = try await enrichJinaRowsWithReader(rows)
        }

        return BuiltinSearchToolOutput(
            provider: .jina,
            query: args.query,
            resultCount: rows.count,
            results: rows
        )
    }

    private func enrichJinaRowsWithReader(_ rows: [SearchCitationRow]) async throws -> [SearchCitationRow] {
        var out: [SearchCitationRow] = []
        out.reserveCapacity(rows.count)

        for (index, row) in rows.enumerated() {
            guard index < 3 else {
                out.append(row)
                continue
            }
            if let snippet = try await fetchJinaReaderSnippet(for: row.url) {
                out.append(
                    SearchCitationRow(
                        title: row.title,
                        url: row.url,
                        snippet: snippet,
                        publishedAt: row.publishedAt,
                        source: row.source
                    )
                )
            } else {
                out.append(row)
            }
        }

        return out
    }

    private func fetchJinaReaderSnippet(for urlString: String) async throws -> String? {
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        let readerURL = try validatedURL("https://r.jina.ai/\(encoded)")
        var request = URLRequest(url: readerURL)
        request.httpMethod = "GET"
        let (data, _) = try await networkManager.sendRequest(request)
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let condensed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !condensed.isEmpty else { return nil }
        return String(condensed.prefix(500))
    }

    // MARK: - Firecrawl

    func searchFirecrawl(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        var request = URLRequest(url: try validatedURL("https://api.firecrawl.dev/v2/search"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let maxResults = clamp(args.maxResults, min: 1, max: 50)
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

    // MARK: - Tavily

    func searchTavily(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        var request = URLRequest(url: try validatedURL("https://api.tavily.com/search"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        // max_results: Tavily supports 0-20
        let clampedMax = clamp(args.maxResults, min: 0, max: 20)

        var body: [String: Any] = [
            "query": args.query,
            "max_results": clampedMax
        ]

        // Tavily supports "basic", "fast", "advanced", and "ultra-fast".
        let searchDepth = tavilySearchDepthValue(
            normalizedTrimmedString(route.overrides?.tavilySearchDepth)
                ?? route.settings.tavilySearchDepth
        )
        body["search_depth"] = searchDepth

        // topic: "general" | "news" | "finance"
        let topic = tavilyTopicValue(
            normalizedTrimmedString(route.overrides?.tavilyTopic)
                ?? route.settings.tavilyTopic
        )
        body["topic"] = topic

        // Prefer exact recency windows over bucketed time ranges.
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
            // Tavily excludes up to 150 domains (include_domains supports a larger limit).
            body["exclude_domains"] = Array(args.excludeDomains.prefix(150))
        }

        // include_raw_content: include cleaned markdown/snippets when requested
        if args.includeRawContent {
            body["include_raw_content"] = "markdown"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await networkManager.sendRequest(request)
        let json = try parseJSONObject(data)

        let rows = parseArray(json["results"]).prefix(clampedMax).compactMap { item -> SearchCitationRow? in
            guard let url = firstString(in: item, keys: ["url"]) else { return nil }
            let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
            // "content" is the primary snippet; "raw_content" is full page text when requested
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

    // MARK: - Perplexity Search API

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

        // Per official Search API docs, max_results range is 1...20.
        let clampedMax = clamp(args.maxResults, min: 1, max: 20)
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
            // Keep provider default page budget to avoid unnecessary cost/latency spikes.
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
