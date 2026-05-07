import Foundation

extension ResponsesAPIResponse {
    var outputTextParts: [String] {
        output.flatMap { item in
            switch item.type {
            case "message":
                return item.content?.compactMap { $0.type == "output_text" ? $0.text : nil } ?? []
            case "reasoning":
                return item.summary?.compactMap { $0.type == "summary_text" ? $0.text : nil } ?? []
            default:
                return []
            }
        }
    }

    var incompleteNoticeMarkdown: String? {
        ResponsesAPIIncompleteDetails.noticeMarkdown(
            status: status,
            reason: incompleteDetails?.reason
        )
    }

    var searchActivities: [SearchActivity] {
        var out: [SearchActivity] = []

        for (index, item) in output.enumerated() {
            if item.type == "web_search_call",
               let id = item.id {
                out.append(
                    SearchActivity(
                        id: id,
                        type: item.action?.type ?? "web_search_call",
                        status: SearchActivityStatus(rawValue: item.status ?? "in_progress"),
                        arguments: ResponsesAPIResponse.searchActivityArguments(from: item.action),
                        outputIndex: index
                    )
                )
            }

            if item.type == "message" {
                let arguments = ResponsesAPIResponse.citationArguments(from: item.content)
                if !arguments.isEmpty {
                    let baseID = item.id ?? "message_\(index)"
                    out.append(
                        SearchActivity(
                            id: "\(baseID):citations",
                            type: "url_citation",
                            status: .completed,
                            arguments: arguments,
                            outputIndex: index
                        )
                    )
                }
            }
        }

        return out
    }

    static func searchActivityArguments(from action: ResponsesAPIOutputItemAddedEvent.WebSearchAction?) -> [String: AnyCodable] {
        guard let action else { return [:] }
        var out: [String: AnyCodable] = [:]
        if let query = action.query, !query.isEmpty {
            out["query"] = AnyCodable(query)
        }
        if let queries = action.queries, !queries.isEmpty {
            out["queries"] = AnyCodable(queries)
        }
        if let url = action.url, !url.isEmpty {
            out["url"] = AnyCodable(url)
        }
        if let pattern = action.pattern, !pattern.isEmpty {
            out["pattern"] = AnyCodable(pattern)
        }
        if let sources = action.sources, !sources.isEmpty {
            out["sources"] = AnyCodable(
                sources.map { source in
                    var payload: [String: Any] = [
                        "type": source.type,
                        "url": source.url
                    ]
                    if let title = source.title, !title.isEmpty {
                        payload["title"] = title
                    }
                    if let snippet = normalizedSearchPreviewText(source.snippet ?? source.description) {
                        payload["snippet"] = snippet
                    }
                    return payload
                }
            )
        }
        return out
    }

    static func citationArguments(from content: [ResponsesAPIOutputContent]?) -> [String: AnyCodable] {
        guard let content else { return [:] }

        var sourcePayloads: [[String: Any]] = []
        var seenURLs: Set<String> = []

        for part in content where part.type == "output_text" {
            for annotation in part.annotations ?? [] {
                guard annotation.type == "url_citation" else { continue }
                guard let rawURL = normalizedTrimmedString(annotation.url) else {
                    continue
                }

                let dedupeKey = rawURL.lowercased()
                guard !seenURLs.contains(dedupeKey) else { continue }
                seenURLs.insert(dedupeKey)

                var source: [String: Any] = [
                    "type": annotation.type,
                    "url": rawURL
                ]
                if let title = normalizedTrimmedString(annotation.title) {
                    source["title"] = title
                }
                if let snippet = citationPreviewSnippet(
                    text: part.text,
                    startIndex: annotation.startIndex,
                    endIndex: annotation.endIndex
                ) {
                    source["snippet"] = snippet
                }
                sourcePayloads.append(source)
            }
        }

        guard !sourcePayloads.isEmpty else { return [:] }

        var args: [String: AnyCodable] = [
            "sources": AnyCodable(sourcePayloads)
        ]
        if let firstSource = sourcePayloads.first,
           let firstURL = firstSource["url"] as? String {
            args["url"] = AnyCodable(firstURL)
            if let firstTitle = firstSource["title"] as? String, !firstTitle.isEmpty {
                args["title"] = AnyCodable(firstTitle)
            }
        }
        return args
    }

    func toUsage() -> Usage? {
        usage?.toUsage()
    }
}

// MARK: - Citation Utilities

func normalizedSearchPreviewText(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let collapsed = raw
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    guard let collapsed = normalizedTrimmedString(collapsed) else { return nil }
    if collapsed.count <= 420 {
        return collapsed
    }
    let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 420)
    return String(collapsed[..<endIndex]) + "\u{2026}"
}

func citationPreviewSnippet(
    text: String?,
    startIndex: Int?,
    endIndex: Int?
) -> String? {
    guard let text, !text.isEmpty else { return nil }
    guard let startIndex, let endIndex,
          startIndex >= 0, endIndex >= startIndex else {
        return nil
    }

    let textLength = text.count
    guard startIndex < textLength else { return nil }

    // OpenAI Responses annotations use character offsets with inclusive end_index.
    let clampedEnd = min(endIndex, textLength - 1)
    guard clampedEnd >= startIndex else { return nil }

    let contextRadius = 80
    let windowStart = max(0, startIndex - contextRadius)
    let windowEnd = min(textLength - 1, clampedEnd + contextRadius)
    guard windowEnd >= windowStart else { return nil }

    let snippetStart = text.index(text.startIndex, offsetBy: windowStart)
    let snippetEnd = text.index(text.startIndex, offsetBy: windowEnd)
    let snippet = String(text[snippetStart...snippetEnd])
    return normalizedSearchPreviewText(snippet)
}
