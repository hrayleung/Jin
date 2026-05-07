import Foundation

extension BuiltinSearchToolHub {
    func searchJina(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
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
}
