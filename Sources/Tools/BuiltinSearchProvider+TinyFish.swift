import Foundation

extension BuiltinSearchToolHub {
    /// TinyFish Search does not expose a result-count parameter. Each page returns about
    /// 10 hits; `page` is 0-indexed with a documented maximum of 10.
    /// https://docs.tinyfish.ai/search-api/reference
    static let tinyfishMaxResultsRange = 1...50
    static let tinyfishMaxPage = 10
    static let tinyfishFetchURLLimit = 10
    static let tinyfishFetchedSnippetLimit = 8_000
    static let tinyfishRecencyMinutesRange = 1...5_256_000

    func searchTinyFish(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        if args.maxResults == 0 {
            return .empty(provider: .tinyfish, query: args.query)
        }

        let desiredMaxResults = args.maxResults.clamped(to: Self.tinyfishMaxResultsRange)
        let domainType = TinyFishDomainType.resolved(from: route.settings.tinyfishDomainType)
        var rows: [SearchCitationRow] = []
        rows.reserveCapacity(desiredMaxResults)

        for page in 0...Self.tinyfishMaxPage {
            guard rows.count < desiredMaxResults else { break }

            guard let url = Self.makeTinyFishSearchURL(
                query: args.query,
                location: route.settings.tinyfishLocation,
                language: route.settings.tinyfishLanguage,
                includeDomains: args.includeDomains,
                excludeDomains: args.excludeDomains,
                recencyDays: args.recencyDays,
                domainType: domainType,
                page: page
            ) else {
                throw LLMError.invalidRequest(message: "Failed to construct TinyFish search URL.")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue(route.apiKey, forHTTPHeaderField: "X-API-Key")
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            let (data, _) = try await networkManager.sendRequest(request)
            let json = try parseJSONObject(data)
            let pageRows = Self.makeTinyFishRows(from: parseArray(json["results"]), maxResults: desiredMaxResults - rows.count)
            if pageRows.isEmpty {
                break
            }
            rows.append(contentsOf: pageRows)
        }

        if args.includeRawContent || args.fetchPageContent {
            rows = try await fetchTinyFishPages(rows, apiKey: route.apiKey)
        }

        return BuiltinSearchToolOutput(
            provider: .tinyfish,
            query: args.query,
            resultCount: rows.count,
            results: rows
        )
    }

    private func fetchTinyFishPages(_ rows: [SearchCitationRow], apiKey: String) async throws -> [SearchCitationRow] {
        let urls = Array(rows.map(\.url).prefix(Self.tinyfishFetchURLLimit))
        guard !urls.isEmpty else { return rows }

        var request = URLRequest(url: try validatedURL("https://api.fetch.tinyfish.ai"))
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.makeTinyFishFetchBody(urls: urls))

        let (data, _) = try await networkManager.sendRequest(request)
        let json = try parseJSONObject(data)
        return Self.mergeTinyFishFetchedContent(rows: rows, fetchResults: parseArray(json["results"]))
    }

    /// Pure builder for `GET https://api.search.tinyfish.ai`, exposed for tests.
    nonisolated static func makeTinyFishSearchURL(
        query: String,
        location: String?,
        language: String?,
        includeDomains: [String],
        excludeDomains: [String],
        recencyDays: Int?,
        domainType: TinyFishDomainType?,
        page: Int
    ) -> URL? {
        var components = URLComponents(string: "https://api.search.tinyfish.ai")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "query", value: query)
        ]

        if let location = normalizedTrimmedString(location) {
            items.append(URLQueryItem(name: "location", value: location))
        }
        if let language = normalizedTrimmedString(language) {
            items.append(URLQueryItem(name: "language", value: language))
        }

        let includes = includeDomains.compactMap { $0.trimmedNonEmpty }
        if !includes.isEmpty {
            items.append(URLQueryItem(name: "include_domains", value: includes.joined(separator: ",")))
        }
        let excludes = excludeDomains.compactMap { $0.trimmedNonEmpty }
        if !excludes.isEmpty {
            items.append(URLQueryItem(name: "exclude_domains", value: excludes.joined(separator: ",")))
        }

        if let domainType, domainType != .web {
            items.append(URLQueryItem(name: "domain_type", value: domainType.rawValue))
        }

        // Date/recency filters are not supported for research_paper; use pub_year_* instead.
        if domainType != .researchPaper, let recencyDays, recencyDays > 0 {
            let minutes = (recencyDays * 24 * 60).clamped(to: tinyfishRecencyMinutesRange)
            items.append(URLQueryItem(name: "recency_minutes", value: String(minutes)))
        }

        if page > 0 {
            items.append(URLQueryItem(name: "page", value: String(min(page, tinyfishMaxPage))))
        }

        components?.queryItems = items
        return components?.url
    }

    nonisolated static func makeTinyFishFetchBody(urls: [String]) -> [String: Any] {
        [
            "urls": Array(urls.prefix(tinyfishFetchURLLimit)),
            "format": "markdown"
        ]
    }

    /// Maps TinyFish Search `results[]` into citation rows, including news/research extras.
    nonisolated static func makeTinyFishRows(from raw: [[String: Any]], maxResults: Int) -> [SearchCitationRow] {
        let cap = max(0, maxResults)
        guard cap > 0 else { return [] }

        var seenURLs = Set<String>()
        var rows: [SearchCitationRow] = []
        rows.reserveCapacity(min(cap, raw.count))

        for item in raw {
            guard rows.count < cap else { break }
            guard let url = firstString(in: item, keys: ["url", "pdf_url"]) else { continue }
            guard seenURLs.insert(url).inserted else { continue }

            let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
            let snippet = tinyFishSnippet(from: item)
            let publishedAt = firstString(in: item, keys: ["date"])
                ?? tinyFishYearString(from: item["year"])
            let source = firstString(in: item, keys: ["publisher", "site_name", "venue"])
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

    nonisolated static func mergeTinyFishFetchedContent(
        rows: [SearchCitationRow],
        fetchResults: [[String: Any]]
    ) -> [SearchCitationRow] {
        var contentByURL: [String: String] = [:]
        for item in fetchResults {
            guard let text = firstString(in: item, keys: ["text"]) else { continue }
            let clipped = String(text.prefix(tinyfishFetchedSnippetLimit))
            if let url = firstString(in: item, keys: ["url"]) {
                contentByURL[url] = clipped
            }
            if let finalURL = firstString(in: item, keys: ["final_url"]) {
                contentByURL[finalURL] = clipped
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

    nonisolated static func tinyFishSnippet(from item: [String: Any]) -> String? {
        var parts: [String] = []

        if let snippet = firstString(in: item, keys: ["snippet"]) {
            parts.append(snippet)
        }

        if let authors = item["authors"] as? [String] {
            let joined = authors.compactMap { $0.trimmedNonEmpty }.joined(separator: ", ")
            if !joined.isEmpty {
                parts.append("Authors: \(joined)")
            }
        } else if let authors = item["authors"] as? [Any] {
            let joined = authors.compactMap { $0 as? String }.compactMap { $0.trimmedNonEmpty }.joined(separator: ", ")
            if !joined.isEmpty {
                parts.append("Authors: \(joined)")
            }
        }

        if let venue = firstString(in: item, keys: ["venue"]) {
            parts.append(venue)
        }

        if let cited = tinyFishCitedByCount(from: item["cited_by_count"]) {
            parts.append("Cited by \(cited)")
        }

        if let pdf = firstString(in: item, keys: ["pdf_url"]),
           firstString(in: item, keys: ["url"]) != nil {
            parts.append("PDF: \(pdf)")
        }

        guard let joined = parts.joined(separator: "\n").trimmedNonEmpty else { return nil }
        return String(joined.prefix(500))
    }

    nonisolated private static func tinyFishYearString(from value: Any?) -> String? {
        if let year = value as? Int {
            return String(year)
        }
        if let year = value as? Double {
            return String(Int(year.rounded()))
        }
        if let year = value as? String {
            return year.trimmedNonEmpty
        }
        return nil
    }

    nonisolated private static func tinyFishCitedByCount(from value: Any?) -> Int? {
        if let cited = value as? Int {
            return cited
        }
        if let cited = value as? Double {
            return Int(cited.rounded())
        }
        if let cited = value as? String, let intValue = Int(cited.trimmed) {
            return intValue
        }
        return nil
    }
}
