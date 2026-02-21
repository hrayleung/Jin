import Foundation

/// Shared search-activity generation for Google grounding metadata (Gemini + Vertex AI).
///
/// Both GeminiAdapter and VertexAIAdapter produce identical search-activity events
/// from grounding metadata. This utility eliminates that duplication.
enum GoogleGroundingSearchActivities {

    // MARK: - Portable Grounding Types

    /// A provider-agnostic representation of Google grounding metadata.
    struct GroundingMetadata {
        let webSearchQueries: [String]?
        let retrievalQueries: [String]?
        let groundingChunks: [GroundingChunk]?
        let groundingSupports: [GroundingSupport]?
        let searchEntryPoint: SearchEntryPoint?

        struct GroundingChunk {
            let webURI: String?
            let webTitle: String?
        }

        struct GroundingSupport {
            let segmentText: String?
            let groundingChunkIndices: [Int]?
        }

        struct SearchEntryPoint {
            let sdkBlob: String?
        }
    }

    // MARK: - Public API

    /// Generates search-activity stream events from grounding metadata.
    ///
    /// - Parameters:
    ///   - grounding: The grounding metadata to convert.
    ///   - searchPrefix: ID prefix for search events (e.g. "gemini-search" or "vertex-search").
    ///   - openPrefix: ID prefix for open-page events (e.g. "gemini-open" or "vertex-open").
    ///   - searchURLPrefix: ID prefix for fallback search-suggestion URL events.
    /// - Returns: An array of `.searchActivity` stream events.
    static func events(
        from grounding: GroundingMetadata?,
        searchPrefix: String,
        openPrefix: String,
        searchURLPrefix: String
    ) -> [StreamEvent] {
        guard let grounding else { return [] }
        var out: [StreamEvent] = []

        let orderedQueries = mergedGroundingQueries(from: grounding)
        for (index, query) in orderedQueries.enumerated() {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            out.append(
                .searchActivity(
                    SearchActivity(
                        id: activityID(prefix: searchPrefix, value: trimmed, index: index),
                        type: "search",
                        status: .completed,
                        arguments: ["query": AnyCodable(trimmed)],
                        outputIndex: nil,
                        sequenceNumber: index
                    )
                )
            )
        }

        var sourceEvents: [StreamEvent] = []
        var seenSourceURLKeys: Set<String> = []
        var sourceSequence = 0
        let sourceSequenceBase = orderedQueries.count
        func appendSourceActivity(url rawURL: String?, title rawTitle: String?, idPrefix: String) {
            let url = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !url.isEmpty else { return }
            let dedupeKey = url.lowercased()
            guard seenSourceURLKeys.insert(dedupeKey).inserted else { return }

            var args: [String: AnyCodable] = ["url": AnyCodable(url)]
            if let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                args["title"] = AnyCodable(title)
            }

            sourceEvents.append(
                .searchActivity(
                    SearchActivity(
                        id: activityID(prefix: idPrefix, value: url, index: sourceSequence),
                        type: "open_page",
                        status: .completed,
                        arguments: args,
                        outputIndex: nil,
                        sequenceNumber: sourceSequenceBase + sourceSequence
                    )
                )
            )
            sourceSequence += 1
        }

        for chunk in grounding.groundingChunks ?? [] {
            appendSourceActivity(
                url: chunk.webURI,
                title: chunk.webTitle,
                idPrefix: openPrefix
            )
        }

        if sourceEvents.isEmpty {
            for suggestion in GoogleGroundingSearchSuggestionParser.parse(sdkBlob: grounding.searchEntryPoint?.sdkBlob) {
                appendSourceActivity(url: suggestion.url, title: suggestion.query, idPrefix: searchURLPrefix)
            }
        }

        out.append(contentsOf: sourceEvents)
        return out
    }

    // MARK: - Private Helpers

    private static func mergedGroundingQueries(from grounding: GroundingMetadata) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []

        for query in (grounding.webSearchQueries ?? []) + (grounding.retrievalQueries ?? []) {
            let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(query)
        }

        return out
    }

    private static func activityID(prefix: String, value: String, index: Int) -> String {
        let normalized = value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let suffix = String(normalized.prefix(80))
        return "\(prefix)_\(index)_\(suffix)"
    }
}
