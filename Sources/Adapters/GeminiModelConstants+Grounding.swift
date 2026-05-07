import Foundation

extension GeminiModelConstants {
    /// Converts a Google grounding metadata to the shared grounding format.
    static func toSharedGrounding(_ g: GoogleGenerateContentResponse.GroundingMetadata) -> GoogleGroundingSearchActivities.GroundingMetadata {
        GoogleGroundingSearchActivities.GroundingMetadata(
            webSearchQueries: g.webSearchQueries,
            retrievalQueries: g.retrievalQueries,
            groundingChunks: g.groundingChunks?.map {
                .init(
                    webURI: $0.web?.uri,
                    webTitle: $0.web?.title,
                    mapsURI: $0.maps?.uri,
                    mapsTitle: $0.maps?.title,
                    mapsPlaceId: $0.maps?.placeId
                )
            },
            groundingSupports: g.groundingSupports?.map {
                .init(segmentText: $0.segment?.text, groundingChunkIndices: $0.groundingChunkIndices)
            },
            searchEntryPoint: g.searchEntryPoint.map {
                .init(sdkBlob: $0.sdkBlob)
            }
        )
    }
}
