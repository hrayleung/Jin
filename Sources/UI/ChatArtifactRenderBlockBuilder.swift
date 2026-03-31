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

        for part in content {
            appendBlocks(
                for: part,
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
                messageID: messageID,
                timestamp: timestamp,
                artifactVersionCounts: &artifactVersionCounts,
                artifactVersionsByID: &artifactVersionsByID,
                blocks: &blocks
            )
        default:
            blocks.append(.content(part))
        }
    }

    private static func appendArtifactTextBlocks(
        from text: String,
        messageID: UUID,
        timestamp: Date,
        artifactVersionCounts: inout [String: Int],
        artifactVersionsByID: inout OrderedDictionary<String, [RenderedArtifactVersion]>,
        blocks: inout [RenderedMessageBlock]
    ) {
        let parseResult = ArtifactMarkupParser.parse(text)
        let maxIndex = max(parseResult.visibleTextSegments.count, parseResult.artifacts.count)

        for index in 0..<maxIndex {
            appendVisibleTextBlock(at: index, segments: parseResult.visibleTextSegments, blocks: &blocks)
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
        segments: [String],
        blocks: inout [RenderedMessageBlock]
    ) {
        guard index < segments.count else { return }
        let segment = segments[index]
        guard !segment.isEmpty else { return }
        blocks.append(.content(.text(segment)))
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
}
