import Foundation

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
    case content(ContentPart)
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
