import Collections
import Foundation

extension XAIAdapter {

    struct CitationSourceCandidate {
        let url: String
        let title: String?
        let snippet: String?
    }

    func citationSearchActivity(sources: [CitationSourceCandidate]?, responseID: String) -> SearchActivity? {
        citationSearchActivity(sources: sources, responseID: Optional(responseID))
    }

    func citationCandidates(
        citations: [String]?,
        output: [ResponsesAPIOutputItem]?,
        fallbackText: String?
    ) -> [CitationSourceCandidate]? {
        let inlineCandidates = inlineCitationCandidates(from: output)
        if !inlineCandidates.isEmpty {
            return inlineCandidates
        }

        if let citations, !citations.isEmpty {
            let normalized = normalizedCitationCandidates(fromURLs: citations)
            if !normalized.isEmpty {
                return normalized
            }
        }

        guard let fallbackText, !fallbackText.isEmpty else {
            return nil
        }

        let urls = markdownCitationURLs(from: fallbackText)
        let normalized = normalizedCitationCandidates(fromURLs: urls)
        return normalized.isEmpty ? nil : normalized
    }

    func inlineCitationCandidates(from output: [ResponsesAPIOutputItem]?) -> [CitationSourceCandidate] {
        guard let output else { return [] }

        var ordered: [CitationSourceCandidate] = []
        var indexByURLKey: [String: Int] = [:]

        for item in output where item.type == "message" {
            for content in item.content ?? [] where content.type == "output_text" {
                for annotation in content.annotations ?? [] where annotation.type == "url_citation" {
                    guard let rawURL = annotation.url?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !rawURL.isEmpty,
                          let url = URL(string: rawURL),
                          let scheme = url.scheme?.lowercased(),
                          scheme == "http" || scheme == "https" else {
                        continue
                    }

                    let canonical = url.absoluteString
                    let key = canonical.lowercased()
                    let title = normalizedCitationTitle(annotation.title)
                    let snippet = citationPreviewSnippet(
                        text: content.text,
                        startIndex: annotation.startIndex,
                        endIndex: annotation.endIndex
                    )

                    if let existingIndex = indexByURLKey[key] {
                        let existing = ordered[existingIndex]
                        ordered[existingIndex] = CitationSourceCandidate(
                            url: existing.url,
                            title: existing.title ?? title,
                            snippet: preferredSnippet(existing: existing.snippet, candidate: snippet)
                        )
                        continue
                    }

                    indexByURLKey[key] = ordered.count
                    ordered.append(
                        CitationSourceCandidate(
                            url: canonical,
                            title: title,
                            snippet: snippet
                        )
                    )
                }
            }
        }

        return ordered
    }

    func normalizedCitationCandidates(fromURLs urls: [String]) -> [CitationSourceCandidate] {
        guard !urls.isEmpty else { return [] }

        var candidatesByURLKey: OrderedDictionary<String, CitationSourceCandidate> = [:]
        candidatesByURLKey.reserveCapacity(urls.count)

        for raw in urls {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }

            let canonical = url.absoluteString
            let dedupeKey = canonical.lowercased()
            guard candidatesByURLKey[dedupeKey] == nil else { continue }
            candidatesByURLKey[dedupeKey] = CitationSourceCandidate(
                url: canonical,
                title: nil,
                snippet: nil
            )
        }

        return Array(candidatesByURLKey.values)
    }

    func markdownCitationURLs(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let pattern = #"\[\[\d+\]\]\((https?://[^)\s]+)\)|\[\d+\]\((https?://[^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var urls: [String] = []
        urls.reserveCapacity(4)

        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match else { return }

            for group in [1, 2] {
                let groupRange = match.range(at: group)
                guard groupRange.location != NSNotFound,
                      let swiftRange = Range(groupRange, in: text) else {
                    continue
                }
                urls.append(String(text[swiftRange]))
                break
            }
        }

        return urls
    }

    func citationSearchActivity(sources: [CitationSourceCandidate]?, responseID: String?) -> SearchActivity? {
        guard let sources, !sources.isEmpty else { return nil }

        let payloads: [[String: Any]] = sources.map { source in
            var payload: [String: Any] = [
                "type": "url_citation",
                "url": source.url
            ]
            if let title = source.title {
                payload["title"] = title
            }
            if let snippet = source.snippet {
                payload["snippet"] = snippet
            }
            return payload
        }

        var arguments: [String: AnyCodable] = [
            "sources": AnyCodable(payloads)
        ]
        if let first = sources.first {
            arguments["url"] = AnyCodable(first.url)
            if let title = first.title {
                arguments["title"] = AnyCodable(title)
            }
        }

        return SearchActivity(
            id: "\(responseID ?? UUID().uuidString):citations",
            type: "url_citation",
            status: .completed,
            arguments: arguments
        )
    }

    func normalizedCitationTitle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return nil
        }
        return trimmed
    }

    func preferredSnippet(existing: String?, candidate: String?) -> String? {
        guard let candidate else { return existing }
        guard let existing else { return candidate }
        return candidate.count > existing.count ? candidate : existing
    }
}
