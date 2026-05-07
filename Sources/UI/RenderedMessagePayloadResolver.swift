import Foundation

struct RenderedMessagePayloadResolver {
    let loadImageData: @Sendable (DeferredMessagePartReference) async -> Data?
    let loadFileExtractedText: @Sendable (DeferredMessagePartReference) async -> String?

    static let noop = RenderedMessagePayloadResolver(
        loadImageData: { _ in nil },
        loadFileExtractedText: { _ in nil }
    )
}
