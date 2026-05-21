import Collections
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
            let mapsURI: String?
            let mapsTitle: String?
            let mapsPlaceId: String?
            let mapsReviewSnippets: [MapsReviewSnippet]

            init(
                webURI: String? = nil,
                webTitle: String? = nil,
                mapsURI: String? = nil,
                mapsTitle: String? = nil,
                mapsPlaceId: String? = nil,
                mapsReviewSnippets: [MapsReviewSnippet] = []
            ) {
                self.webURI = webURI
                self.webTitle = webTitle
                self.mapsURI = mapsURI
                self.mapsTitle = mapsTitle
                self.mapsPlaceId = mapsPlaceId
                self.mapsReviewSnippets = mapsReviewSnippets
            }
        }

        struct MapsReviewSnippet {
            let reviewID: String?
            let uri: String?
            let title: String?

            init(
                reviewID: String? = nil,
                uri: String? = nil,
                title: String? = nil
            ) {
                self.reviewID = reviewID
                self.uri = uri
                self.title = title
            }
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
            guard let trimmed = query.trimmedNonEmpty else { continue }
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

        var sourceEventsByURLKey: OrderedDictionary<String, StreamEvent> = [:]
        var sourceSequence = 0
        let sourceSequenceBase = orderedQueries.count
        func appendSourceActivity(
            url rawURL: String?,
            title rawTitle: String?,
            idPrefix: String,
            sourceKind: String? = nil,
            mapsPlaceID: String? = nil,
            mapsReviewID: String? = nil,
            mapsReviewSnippets: [String] = [],
            mapsSourceType: String? = nil
        ) {
            guard let url = rawURL?.trimmedNonEmpty else { return }
            let dedupeKey = SearchActivityURLDeduplication.key(for: url)
            let title = rawTitle?.trimmedNonEmpty
            let reviewSnippets = mapsReviewSnippets.compactMap(\.trimmedNonEmpty)

            if case .searchActivity(let existing)? = sourceEventsByURLKey[dedupeKey] {
                var mergedArguments = existing.arguments
                var didChange = false
                let existingWasCanonicalMapsPlace = isCanonicalMapsPlaceActivity(existing.arguments)

                if let title, mergedArguments["title"]?.value as? String == nil {
                    mergedArguments["title"] = AnyCodable(title)
                    didChange = true
                }

                if let sourceKind, !sourceKind.isEmpty,
                   mergedArguments["sourceKind"]?.value as? String == nil {
                    mergedArguments["sourceKind"] = AnyCodable(sourceKind)
                    didChange = true
                }

                if let mapsPlaceID, !mapsPlaceID.isEmpty,
                   mergedArguments["mapsPlaceID"]?.value as? String == nil {
                    mergedArguments["mapsPlaceID"] = AnyCodable(mapsPlaceID)
                    didChange = true
                }

                if let mapsReviewID, !mapsReviewID.isEmpty,
                   mergedArguments["mapsReviewID"]?.value as? String == nil {
                    mergedArguments["mapsReviewID"] = AnyCodable(mapsReviewID)
                    didChange = true
                }

                if !reviewSnippets.isEmpty {
                    let existingSnippets = stringArrayArgument(mergedArguments["mapsReviewSnippets"])
                    let mergedSnippets = deduplicated(existingSnippets + reviewSnippets)
                    if mergedSnippets != existingSnippets {
                        mergedArguments["mapsReviewSnippets"] = AnyCodable(mergedSnippets)
                        didChange = true
                    }
                }

                if let mapsSourceType, !mapsSourceType.isEmpty,
                   mergedArguments["mapsSourceType"]?.value as? String == nil,
                   shouldSetMapsSourceType(
                       mapsSourceType,
                       existingWasCanonicalMapsPlace: existingWasCanonicalMapsPlace
                   ) {
                    mergedArguments["mapsSourceType"] = AnyCodable(mapsSourceType)
                    didChange = true
                }

                guard didChange else {
                    return
                }

                sourceEventsByURLKey[dedupeKey] = .searchActivity(
                    SearchActivity(
                        id: existing.id,
                        type: existing.type,
                        status: existing.status,
                        arguments: mergedArguments,
                        outputIndex: existing.outputIndex,
                        sequenceNumber: existing.sequenceNumber
                    )
                )
                return
            }

            var args: [String: AnyCodable] = ["url": AnyCodable(url)]
            if let title {
                args["title"] = AnyCodable(title)
            }
            if let sourceKind, !sourceKind.isEmpty {
                args["sourceKind"] = AnyCodable(sourceKind)
            }
            if let mapsPlaceID, !mapsPlaceID.isEmpty {
                args["mapsPlaceID"] = AnyCodable(mapsPlaceID)
            }
            if let mapsReviewID, !mapsReviewID.isEmpty {
                args["mapsReviewID"] = AnyCodable(mapsReviewID)
            }
            if !reviewSnippets.isEmpty {
                args["mapsReviewSnippets"] = AnyCodable(deduplicated(reviewSnippets))
            }
            if let mapsSourceType, !mapsSourceType.isEmpty {
                args["mapsSourceType"] = AnyCodable(mapsSourceType)
            }

            sourceEventsByURLKey[dedupeKey] = .searchActivity(
                SearchActivity(
                    id: activityID(prefix: idPrefix, value: url, index: sourceSequence),
                    type: "open_page",
                    status: .completed,
                    arguments: args,
                    outputIndex: nil,
                    sequenceNumber: sourceSequenceBase + sourceSequence
                )
            )
            sourceSequence += 1
        }

        for chunk in grounding.groundingChunks ?? [] {
            if let mapsURI = chunk.mapsURI, !mapsURI.isEmpty {
                appendSourceActivity(
                    url: mapsURI,
                    title: chunk.mapsTitle,
                    idPrefix: openPrefix,
                    sourceKind: "google_maps",
                    mapsPlaceID: chunk.mapsPlaceId,
                    mapsReviewSnippets: chunk.mapsReviewSnippets.compactMap(\.title)
                )
                for reviewSnippet in chunk.mapsReviewSnippets {
                    appendSourceActivity(
                        url: reviewSnippet.uri,
                        title: reviewSnippet.title,
                        idPrefix: openPrefix,
                        sourceKind: "google_maps",
                        mapsPlaceID: chunk.mapsPlaceId,
                        mapsReviewID: reviewSnippet.reviewID,
                        mapsSourceType: "review"
                    )
                }
            } else {
                appendSourceActivity(
                    url: chunk.webURI,
                    title: chunk.webTitle,
                    idPrefix: openPrefix
                )
            }
        }

        if sourceEventsByURLKey.isEmpty {
            for suggestion in GoogleGroundingSearchSuggestionParser.parse(sdkBlob: grounding.searchEntryPoint?.sdkBlob) {
                appendSourceActivity(url: suggestion.url, title: suggestion.query, idPrefix: searchURLPrefix)
            }
        }

        out.append(contentsOf: sourceEventsByURLKey.values)
        return out
    }

    // MARK: - Private Helpers

    private static func mergedGroundingQueries(from grounding: GroundingMetadata) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []

        for query in (grounding.webSearchQueries ?? []) + (grounding.retrievalQueries ?? []) {
            let key = query.trimmedLowercased
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(query)
        }

        return out
    }

    private static func activityID(prefix: String, value: String, index: Int) -> String {
        let normalized = value
            .trimmedLowercased
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let suffix = String(normalized.prefix(80))
        return "\(prefix)_\(index)_\(suffix)"
    }

    private static func stringArrayArgument(_ argument: AnyCodable?) -> [String] {
        if let values = argument?.value as? [String] {
            return values.compactMap(\.trimmedNonEmpty)
        }
        if let values = argument?.value as? [Any] {
            return values.compactMap { value in
                guard let string = value as? String else { return nil }
                return string.trimmedNonEmpty
            }
        }
        return []
    }

    private static func shouldSetMapsSourceType(
        _ mapsSourceType: String,
        existingWasCanonicalMapsPlace: Bool
    ) -> Bool {
        if mapsSourceType.trimmedLowercased == "review",
           existingWasCanonicalMapsPlace {
            return false
        }
        return true
    }

    private static func isCanonicalMapsPlaceActivity(_ arguments: [String: AnyCodable]) -> Bool {
        if stringArgument(arguments["mapsSourceType"])?.trimmedLowercased == "place" {
            return true
        }

        if stringArgument(arguments["mapsReviewID"]) != nil {
            return false
        }

        if stringArgument(arguments["mapsPlaceID"]) != nil
            || stringArgument(arguments["placeId"]) != nil
            || stringArgument(arguments["canonicalPlaceId"]) != nil
            || stringArgument(arguments["placeName"]) != nil {
            return true
        }

        guard let url = stringArgument(arguments["url"])?.trimmedLowercased else {
            return false
        }

        return url.contains("google.com/maps")
            || url.contains("maps.google.")
            || url.contains("maps.app.goo.gl")
    }

    private static func stringArgument(_ argument: AnyCodable?) -> String? {
        guard let value = argument?.value as? String else { return nil }
        return value.trimmedNonEmpty
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for value in values {
            let key = value.trimmedLowercased
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            out.append(value)
        }
        return out
    }
}
