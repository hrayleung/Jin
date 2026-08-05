import Foundation

extension BuiltinSearchToolHub {
    /// Jin caps Firecrawl `/v2/search` results at 50. The API itself accepts 1...100
    /// (https://docs.firecrawl.dev/api-reference/endpoint/search); 50 is a deliberate
    /// product cap. Single source of truth for the request limit and the result cap.
    static let firecrawlMaxResultsRange = 1...50

    func searchFirecrawl(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        var request = URLRequest(url: try validatedURL("https://api.firecrawl.dev/v2/search"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let body = Self.makeFirecrawlRequestBody(args: args, settings: route.settings, overrides: route.overrides)
        let maxResults = args.maxResults.clamped(to: Self.firecrawlMaxResultsRange)

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
        let maxResults = args.maxResults.clamped(to: firecrawlMaxResultsRange)

        var body: [String: Any] = [
            "query": args.query,
            "limit": maxResults,
            "ignoreInvalidURLs": true
        ]

        if let recency = args.recencyDays {
            body["tbs"] = firecrawlRecencyTBS(recencyDays: recency)
        }

        if let country = (overrides?.firecrawlCountry?.trimmedNonEmpty ?? settings.firecrawlCountry?.trimmedNonEmpty) {
            body["country"] = country
        }

        // Native domain filters (mutually exclusive per Firecrawl docs). Prefer include.
        let domainFilters = firecrawlDomainFilters(
            includeDomains: args.includeDomains,
            excludeDomains: args.excludeDomains
        )
        if let includes = domainFilters.includeDomains {
            body["includeDomains"] = includes
        } else if let excludes = domainFilters.excludeDomains {
            body["excludeDomains"] = excludes
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

    /// Builds Firecrawl domain filter arrays. Include and exclude are mutually exclusive;
    /// when both are present, include wins (graceful degrade, same policy as Perplexity).
    /// Hostnames only (no protocol/path). Cap at 20 entries.
    nonisolated static func firecrawlDomainFilters(
        includeDomains: [String],
        excludeDomains: [String]
    ) -> (includeDomains: [String]?, excludeDomains: [String]?) {
        let includes = firecrawlNormalizedHostnames(includeDomains)
        if !includes.isEmpty {
            return (includes, nil)
        }
        let excludes = firecrawlNormalizedHostnames(excludeDomains)
        if !excludes.isEmpty {
            return (nil, excludes)
        }
        return (nil, nil)
    }

    nonisolated static func firecrawlNormalizedHostnames(_ domains: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(min(20, domains.count))

        for raw in domains {
            guard let hostname = firecrawlHostname(from: raw) else { continue }
            let key = hostname.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(hostname)
            if result.count >= 20 { break }
        }
        return result
    }

    /// Extracts a bare hostname from a domain-ish string (strips scheme/path/port).
    nonisolated static func firecrawlHostname(from raw: String) -> String? {
        guard let trimmed = raw.trimmedNonEmpty else { return nil }
        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            return host
        }
        // Bare host or host/path without scheme.
        let withoutScheme: String
        if let range = trimmed.range(of: "://") {
            withoutScheme = String(trimmed[range.upperBound...])
        } else {
            withoutScheme = trimmed
        }
        let hostPart = withoutScheme.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? withoutScheme
        let hostOnly = hostPart.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? hostPart
        return hostOnly.trimmedNonEmpty
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
        // Floor of 0 (not 1) is deliberate: this pure builder is called directly by tests
        // with arbitrary counts, and 0 must yield an empty list. Production callers always
        // pass a value already clamped to `firecrawlMaxResultsRange` (>= 1).
        let cap = maxResults.clamped(to: 0...firecrawlMaxResultsRange.upperBound)
        guard cap > 0 else { return [] }

        var seenURLs = Set<String>()
        var rows: [SearchCitationRow] = []
        rows.reserveCapacity(min(cap, raw.count))

        for item in raw {
            guard rows.count < cap else { break }
            guard let url = firstString(in: item, keys: ["url", "link", "imageUrl"]) else { continue }
            guard seenURLs.insert(url).inserted else { continue }

            let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
            let snippet = firstString(in: item, keys: ["description", "snippet", "markdown", "summary", "content"])
            let publishedAt = firstString(in: item, keys: ["publishedDate", "published", "date"])
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
}
