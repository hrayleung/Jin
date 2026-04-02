import Foundation

enum MessageRenderMode: Equatable, Sendable {
    case fullWeb
    case nativeText
    case collapsedPreview
}

struct DeferredMessagePartReference: Hashable, Sendable {
    let messageID: UUID
    let partIndex: Int
}

struct RenderedImageContent: Sendable {
    let mimeType: String
    let inlineData: Data?
    let url: URL?
    let assetDisposition: MediaAssetDisposition
    let deferredSource: DeferredMessagePartReference?

    var remoteURL: URL? {
        guard let url, !url.isFileURL else { return nil }
        return url
    }
}

struct RenderedFileContent: Sendable {
    let mimeType: String
    let filename: String
    let url: URL?
    let extractedText: String?
    let hasDeferredExtractedText: Bool
    let deferredSource: DeferredMessagePartReference?

    var hasExtractedText: Bool {
        if let extractedText,
           !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return hasDeferredExtractedText
    }
}

enum RenderedContentPart: Sendable {
    case text(String)
    case quote(QuoteContent)
    case image(RenderedImageContent)
    case video(VideoContent)
    case file(RenderedFileContent)
    case audio(AudioContent)
    case thinking(ThinkingBlock)
    case redactedThinking(RedactedThinkingBlock)
}

struct LightweightMessagePreview: Hashable, Sendable {
    let headline: String
    let body: String
    let lineCount: Int
    let containsCode: Bool
}

struct RenderedArtifactVersion: Identifiable, Hashable, Sendable {
    let artifactID: String
    let version: Int
    let title: String
    let contentType: ArtifactContentType
    let content: String
    let sourceMessageID: UUID
    let sourceTimestamp: Date

    var id: String {
        "\(artifactID)#\(version)"
    }
}

enum RenderedMessageBlock: Sendable {
    case content(anchorID: String, part: RenderedContentPart)
    case artifact(RenderedArtifactVersion)
}

struct ArtifactCatalog: Sendable {
    let orderedArtifactIDs: [String]
    let versionsByArtifactID: [String: [RenderedArtifactVersion]]

    static let empty = ArtifactCatalog(orderedArtifactIDs: [], versionsByArtifactID: [:])

    var isEmpty: Bool {
        orderedArtifactIDs.isEmpty
    }

    var latestVersion: RenderedArtifactVersion? {
        orderedArtifactIDs.compactMap { latestVersion(for: $0) }.last
    }

    func versions(for artifactID: String) -> [RenderedArtifactVersion] {
        versionsByArtifactID[artifactID] ?? []
    }

    func latestVersion(for artifactID: String) -> RenderedArtifactVersion? {
        versions(for: artifactID).last
    }

    func version(artifactID: String, version: Int?) -> RenderedArtifactVersion? {
        let candidates = versions(for: artifactID)
        guard !candidates.isEmpty else { return nil }

        if let version {
            return candidates.first(where: { $0.version == version }) ?? candidates.last
        }

        return candidates.last
    }
}
