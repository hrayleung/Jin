import Collections
import Foundation

enum ChatArtifactRenderBlockBuilder {
    static func renderedBlocks(
        content: [RenderedContentPart],
        role: MessageRole,
        messageID: UUID,
        timestamp: Date,
        artifactVersionCounts: inout [String: Int],
        artifactVersionsByID: inout OrderedDictionary<String, [RenderedArtifactVersion]>
    ) -> [RenderedMessageBlock] {
        var blocks: [RenderedMessageBlock] = []
        var partAnchorOccurrences: [String: Int] = [:]

        for part in content {
            let baseComponent = part.stableAnchorComponent
            let occurrence = partAnchorOccurrences[baseComponent, default: 0]
            partAnchorOccurrences[baseComponent] = occurrence + 1
            appendBlocks(
                for: part,
                stableAnchorBase: "\(baseComponent):\(occurrence)",
                role: role,
                messageID: messageID,
                timestamp: timestamp,
                artifactVersionCounts: &artifactVersionCounts,
                artifactVersionsByID: &artifactVersionsByID,
                blocks: &blocks
            )
        }

        return blocks
    }

    private static func appendBlocks(
        for part: RenderedContentPart,
        stableAnchorBase: String,
        role: MessageRole,
        messageID: UUID,
        timestamp: Date,
        artifactVersionCounts: inout [String: Int],
        artifactVersionsByID: inout OrderedDictionary<String, [RenderedArtifactVersion]>,
        blocks: inout [RenderedMessageBlock]
    ) {
        switch part {
        case .redactedThinking:
            return
        case .text(let text) where role == .assistant:
            appendArtifactTextBlocks(
                from: text,
                anchorPrefix: stableAnchorPrefix(messageID: messageID, stableAnchorBase: stableAnchorBase),
                messageID: messageID,
                timestamp: timestamp,
                artifactVersionCounts: &artifactVersionCounts,
                artifactVersionsByID: &artifactVersionsByID,
                blocks: &blocks
            )
        default:
            blocks.append(.content(anchorID: stableAnchorPrefix(messageID: messageID, stableAnchorBase: stableAnchorBase), part: part))
        }
    }

    private static func appendArtifactTextBlocks(
        from text: String,
        anchorPrefix: String,
        messageID: UUID,
        timestamp: Date,
        artifactVersionCounts: inout [String: Int],
        artifactVersionsByID: inout OrderedDictionary<String, [RenderedArtifactVersion]>,
        blocks: inout [RenderedMessageBlock]
    ) {
        let parseResult = ArtifactMarkupParser.parse(text)
        let maxIndex = max(parseResult.visibleTextSegments.count, parseResult.artifacts.count)
        var segmentOccurrences: [String: Int] = [:]

        for index in 0..<maxIndex {
            appendVisibleTextBlock(
                at: index,
                anchorPrefix: anchorPrefix,
                segmentOccurrences: &segmentOccurrences,
                segments: parseResult.visibleTextSegments,
                blocks: &blocks
            )
            appendArtifactBlock(
                at: index,
                artifacts: parseResult.artifacts,
                messageID: messageID,
                timestamp: timestamp,
                artifactVersionCounts: &artifactVersionCounts,
                artifactVersionsByID: &artifactVersionsByID,
                blocks: &blocks
            )
        }
    }

    private static func appendVisibleTextBlock(
        at index: Int,
        anchorPrefix: String,
        segmentOccurrences: inout [String: Int],
        segments: [String],
        blocks: inout [RenderedMessageBlock]
    ) {
        guard index < segments.count else { return }
        let segment = segments[index]
        guard !segment.isEmpty else { return }
        let segmentHash = stableStringHash(segment)
        let occurrence = segmentOccurrences[segmentHash, default: 0]
        segmentOccurrences[segmentHash] = occurrence + 1
        blocks.append(.content(anchorID: "\(anchorPrefix):segment:\(segmentHash):\(occurrence)", part: .text(segment)))
    }

    private static func appendArtifactBlock(
        at index: Int,
        artifacts: [ParsedArtifact],
        messageID: UUID,
        timestamp: Date,
        artifactVersionCounts: inout [String: Int],
        artifactVersionsByID: inout OrderedDictionary<String, [RenderedArtifactVersion]>,
        blocks: inout [RenderedMessageBlock]
    ) {
        guard index < artifacts.count else { return }
        let artifact = artifacts[index]
        let nextVersion = (artifactVersionCounts[artifact.artifactID] ?? 0) + 1
        artifactVersionCounts[artifact.artifactID] = nextVersion

        let version = RenderedArtifactVersion(
            artifactID: artifact.artifactID,
            version: nextVersion,
            title: artifact.title,
            contentType: artifact.contentType,
            content: artifact.content,
            sourceMessageID: messageID,
            sourceTimestamp: timestamp
        )
        artifactVersionsByID[artifact.artifactID, default: []].append(version)
        blocks.append(.artifact(version))
    }

    private static func stableAnchorPrefix(messageID: UUID, stableAnchorBase: String) -> String {
        "\(messageID.uuidString):content:\(stableAnchorBase)"
    }
}
