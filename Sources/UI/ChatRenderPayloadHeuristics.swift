import Foundation

enum ChatRenderPayloadHeuristics {
    private static let asyncBuildMessageCountThreshold = 80
    private static let asyncBuildTotalPayloadByteThreshold = 32_000
    private static let asyncBuildSingleMessagePayloadByteThreshold = 12_000

    static func shouldBuildRenderContextAsynchronously(from orderedMessages: [MessageEntity]) -> Bool {
        guard !orderedMessages.isEmpty else { return false }

        var totalPayloadBytes = 0
        var largestMessagePayloadBytes = 0

        for entity in orderedMessages {
            let payloadBytes = estimatedPayloadBytes(for: entity)
            totalPayloadBytes += payloadBytes
            largestMessagePayloadBytes = max(largestMessagePayloadBytes, payloadBytes)
        }

        return orderedMessages.count >= asyncBuildMessageCountThreshold
            || totalPayloadBytes >= asyncBuildTotalPayloadByteThreshold
            || largestMessagePayloadBytes >= asyncBuildSingleMessagePayloadByteThreshold
    }

    private static func estimatedPayloadBytes(for entity: MessageEntity) -> Int {
        let payloads: [Data?] = [
            entity.toolCallsData,
            entity.toolResultsData,
            entity.searchActivitiesData,
            entity.codeExecutionActivitiesData,
            entity.codexToolActivitiesData,
            entity.agentToolActivitiesData,
            entity.perMessageMCPServerNamesData,
            entity.responseMetricsData
        ]

        return entity.contentData.count + payloads.reduce(0) { partialResult, payload in
            partialResult + (payload?.count ?? 0)
        }
    }
}
