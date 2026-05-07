import Foundation

enum ArtifactWorkspaceSupport {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case preview
        case code

        var id: String { rawValue }

        var title: String {
            switch self {
            case .preview:
                return "Preview"
            case .code:
                return "Code"
            }
        }
    }

    struct Selection: Equatable {
        let artifactID: String?
        let version: Int?
    }

    struct MessageArtifactSelection: Equatable {
        let artifactID: String
        let version: Int?
    }

    static func latestArtifactSelection(
        from message: Message,
        in catalog: ArtifactCatalog
    ) -> MessageArtifactSelection? {
        guard let latestArtifact = latestParsedArtifact(in: message) else { return nil }

        guard let resolvedVersion = catalog.latestVersion(for: latestArtifact.artifactID) else {
            return MessageArtifactSelection(artifactID: latestArtifact.artifactID, version: nil)
        }

        return MessageArtifactSelection(
            artifactID: resolvedVersion.artifactID,
            version: resolvedVersion.version
        )
    }

    static func selectedArtifact(
        in catalog: ArtifactCatalog,
        selectedArtifactID: String?,
        selectedArtifactVersion: Int?
    ) -> RenderedArtifactVersion? {
        guard let artifactID = resolvedArtifactID(
            in: catalog,
            selectedArtifactID: selectedArtifactID
        ) else { return nil }
        return catalog.version(artifactID: artifactID, version: selectedArtifactVersion)
    }

    static func resolvedArtifactID(
        in catalog: ArtifactCatalog,
        selectedArtifactID: String?
    ) -> String? {
        if let selectedArtifactID,
           !catalog.versions(for: selectedArtifactID).isEmpty {
            return selectedArtifactID
        }
        return catalog.latestVersion?.artifactID
    }

    static func availableVersions(
        in catalog: ArtifactCatalog,
        selectedArtifactID: String?
    ) -> [RenderedArtifactVersion] {
        guard let artifactID = resolvedArtifactID(
            in: catalog,
            selectedArtifactID: selectedArtifactID
        ) else { return [] }
        return catalog.versions(for: artifactID)
    }

    static func showsArtifactPicker(in catalog: ArtifactCatalog) -> Bool {
        catalog.orderedArtifactIDs.count > 1
    }

    static func showsVersionPicker(for versions: [RenderedArtifactVersion]) -> Bool {
        versions.count > 1
    }

    static func selectionAfterArtifactChange(
        _ artifactID: String?,
        in catalog: ArtifactCatalog
    ) -> Selection {
        Selection(
            artifactID: artifactID,
            version: catalog.latestVersion(for: artifactID ?? "")?.version
        )
    }

    static func selectionAfterSync(
        in catalog: ArtifactCatalog,
        selectedArtifactID: String?,
        selectedArtifactVersion: Int?
    ) -> Selection {
        guard let latest = catalog.latestVersion else {
            return Selection(artifactID: nil, version: nil)
        }

        if let selectedArtifactID,
           catalog.version(artifactID: selectedArtifactID, version: selectedArtifactVersion) != nil {
            return Selection(artifactID: selectedArtifactID, version: selectedArtifactVersion)
        }

        return Selection(artifactID: latest.artifactID, version: latest.version)
    }

    static func filenameStem(
        for artifact: RenderedArtifactVersion,
        showsVersionPicker: Bool
    ) -> String {
        let fallback = artifact.artifactID.trimmedNonEmpty ?? "artifact"
        let base = artifact.title.trimmedNonEmpty ?? fallback
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleanedScalars = base.unicodeScalars.map { invalid.contains($0) ? "-" : String($0) }
        let name = cleanedScalars.joined().trimmedNonEmpty ?? fallback
        if showsVersionPicker {
            return "\(name)-v\(artifact.version)"
        }
        return name
    }

    static func highlightedCodeMarkdown(for artifact: RenderedArtifactVersion) -> String {
        let fenceLength = max(3, maximumBacktickRunLength(in: artifact.content) + 1)
        let fence = String(repeating: "`", count: fenceLength)
        return "\(fence)\(artifact.contentType.codeFenceLanguage)\n\(artifact.content)\n\(fence)"
    }

    static func maximumBacktickRunLength(in text: String) -> Int {
        var maximum = 0
        var current = 0
        for character in text {
            if character == "`" {
                current += 1
                maximum = max(maximum, current)
            } else {
                current = 0
            }
        }
        return maximum
    }

    private static func latestParsedArtifact(in message: Message) -> ParsedArtifact? {
        var latest: ParsedArtifact?
        for part in message.content {
            guard case .text(let text) = part else { continue }
            latest = ArtifactMarkupParser.parse(text).artifacts.last ?? latest
        }
        return latest
    }
}
