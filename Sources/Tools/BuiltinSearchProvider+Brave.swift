import Collections
import Foundation

extension BuiltinSearchToolHub {
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
}
