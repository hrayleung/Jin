import Foundation

extension AnthropicAdapter {
    func searchActivityFromWebSearchResult(
        contentBlock: AnthropicStreamEvent.ContentBlock,
        outputIndex: Int
    ) -> SearchActivity? {
        guard let results = contentBlock.webSearchResults, !results.isEmpty else {
            return nil
        }

        var sources: [[String: Any]] = []
        var seenURLs: Set<String> = []

        for result in results {
            guard let rawURL = result.url?.trimmedNonEmpty else {
                continue
            }

            let dedupeKey = rawURL.lowercased()
            guard !seenURLs.contains(dedupeKey) else { continue }
            seenURLs.insert(dedupeKey)

            var payload: [String: Any] = [
                "type": result.type ?? "web_search_result",
                "url": rawURL
            ]
            if let title = result.title?.trimmedNonEmpty {
                payload["title"] = title
            }
            if let snippet = (result.snippet ?? result.description)?
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmedNonEmpty {
                payload["snippet"] = snippet
            }
            sources.append(payload)
        }

        guard !sources.isEmpty else { return nil }

        let id = contentBlock.toolUseId ?? contentBlock.id ?? "anthropic_web_search_result_\(outputIndex)"
        let arguments = searchActivityArguments(sources: sources)

        return SearchActivity(
            id: id,
            type: "web_search",
            status: .completed,
            arguments: arguments,
            outputIndex: outputIndex,
            sequenceNumber: outputIndex
        )
    }

    func searchActivityFromTextCitations(
        contentBlock: AnthropicStreamEvent.ContentBlock,
        outputIndex: Int
    ) -> SearchActivity? {
        guard let citations = contentBlock.citations, !citations.isEmpty else {
            return nil
        }

        var sources: [[String: Any]] = []
        var seenURLs: Set<String> = []

        for citation in citations {
            guard citation.type == "web_search_result_location" || citation.type == "search_result_location" else {
                continue
            }

            let rawLocation = citation.url ?? citation.source
            guard let rawURL = rawLocation?.trimmedNonEmpty else {
                continue
            }

            let dedupeKey = rawURL.lowercased()
            guard !seenURLs.contains(dedupeKey) else { continue }
            seenURLs.insert(dedupeKey)

            var payload: [String: Any] = [
                "type": citation.type,
                "url": rawURL
            ]
            if let title = citation.title?.trimmedNonEmpty {
                payload["title"] = title
            }
            if let citedText = citation.citedText?
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmedNonEmpty {
                payload["snippet"] = citedText
            }
            sources.append(payload)
        }

        guard !sources.isEmpty else { return nil }

        let id = "anthropic_citation_\(outputIndex)"
        let arguments = searchActivityArguments(sources: sources)

        return SearchActivity(
            id: id,
            type: "url_citation",
            status: .completed,
            arguments: arguments,
            outputIndex: outputIndex,
            sequenceNumber: outputIndex
        )
    }

    func searchActivityArguments(sources: [[String: Any]]) -> [String: AnyCodable] {
        guard !sources.isEmpty else { return [:] }

        var arguments: [String: AnyCodable] = [
            "sources": AnyCodable(sources)
        ]

        if let first = sources.first,
           let firstURL = first["url"] as? String {
            arguments["url"] = AnyCodable(firstURL)
            if let firstTitle = first["title"] as? String, !firstTitle.isEmpty {
                arguments["title"] = AnyCodable(firstTitle)
            }
        }

        return arguments
    }
}
