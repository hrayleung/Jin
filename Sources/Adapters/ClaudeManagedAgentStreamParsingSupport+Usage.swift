import Foundation

extension ClaudeManagedAgentStreamParsingSupport {
    static func accumulateUsage(
        fromModelRequestEnd object: [String: JSONValue],
        state: inout ClaudeManagedAgentsStreamState
    ) {
        guard let usage = usageFromModelRequestEnd(object) else { return }
        state.accumulatedUsage = mergedUsage(state.accumulatedUsage, with: usage)
    }

    static func usageFromModelRequestEnd(_ object: [String: JSONValue]) -> Usage? {
        let usageObject = object.object(at: ["model_usage"]) ?? object.object(at: ["span", "model_usage"])
        guard let usageObject else { return nil }

        let inputTokens = usageObject.int(at: ["input_tokens"]) ?? 0
        let outputTokens = usageObject.int(at: ["output_tokens"]) ?? 0
        let thinkingTokens = usageObject.int(at: ["thinking_tokens"])
        let cachedTokens = usageObject.int(at: ["cache_read_input_tokens"])
        let cacheCreationTokens = usageObject.int(at: ["cache_creation_input_tokens"])

        guard inputTokens > 0
            || outputTokens > 0
            || thinkingTokens != nil
            || cachedTokens != nil
            || cacheCreationTokens != nil else {
            return nil
        }

        return Usage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            thinkingTokens: thinkingTokens,
            cachedTokens: cachedTokens,
            cacheCreationTokens: cacheCreationTokens
        )
    }

    static func mergedUsage(_ existing: Usage?, with newUsage: Usage) -> Usage {
        guard let existing else { return newUsage }

        return Usage(
            inputTokens: existing.inputTokens + newUsage.inputTokens,
            outputTokens: existing.outputTokens + newUsage.outputTokens,
            thinkingTokens: summedOptional(existing.thinkingTokens, newUsage.thinkingTokens),
            cachedTokens: summedOptional(existing.cachedTokens, newUsage.cachedTokens),
            cacheCreationTokens: summedOptional(existing.cacheCreationTokens, newUsage.cacheCreationTokens),
            cacheWriteTokens: summedOptional(existing.cacheWriteTokens, newUsage.cacheWriteTokens),
            serviceTier: newUsage.serviceTier ?? existing.serviceTier,
            inferenceGeo: newUsage.inferenceGeo ?? existing.inferenceGeo
        )
    }

    static func summedOptional(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case (let lhs?, nil):
            return lhs
        case (nil, let rhs?):
            return rhs
        case (let lhs?, let rhs?):
            return lhs + rhs
        }
    }
}
