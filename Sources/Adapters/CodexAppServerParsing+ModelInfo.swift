import Collections
import Foundation

extension CodexAppServerAdapter {
    nonisolated static func makeModelInfo(from modelObject: [String: JSONValue]) -> ModelInfo? {
        let modelID = trimmedValue(
            modelObject.string(at: ["id"])
                ?? modelObject.string(at: ["model"])
        )
        guard let modelID else { return nil }

        let displayName = trimmedValue(
            modelObject.string(at: ["displayName"])
                ?? modelObject.string(at: ["model"])
        ) ?? modelID

        var capabilities: ModelCapability = [.streaming]
        if modelObject.contains(inArray: "image", at: ["inputModalities"]) {
            capabilities.insert(.vision)
        }

        let supportedEfforts = parseSupportedReasoningEfforts(from: modelObject)
        var reasoningConfig: ModelReasoningConfig?
        if !supportedEfforts.isEmpty {
            capabilities.insert(.reasoning)
            let defaultEffort = parseReasoningEffort(modelObject.string(at: ["defaultReasoningEffort"]))
                ?? supportedEfforts.first
                ?? .medium
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: defaultEffort)
        }

        let contextWindow = firstPositiveInt(
            from: modelObject,
            candidatePaths: [
                ["contextWindow"],
                ["contextLength"],
                ["context_window"],
                ["context_length"],
            ]
        ) ?? fallbackContextWindow

        let catalogMetadata = parseCatalogMetadata(from: modelObject)

        return ModelInfo(
            id: modelID,
            name: displayName,
            capabilities: capabilities,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig,
            catalogMetadata: catalogMetadata
        )
    }

    private nonisolated static func parseCatalogMetadata(from modelObject: [String: JSONValue]) -> ModelCatalogMetadata? {
        let availabilityMessage = trimmedValue(modelObject.string(at: ["availabilityNux", "message"]))
        let upgradeTarget = trimmedValue(
            modelObject.string(at: ["upgradeInfo", "model"])
                ?? modelObject.string(at: ["upgrade"])
        )
        let upgradeMessage = trimmedValue(
            modelObject.string(at: ["upgradeInfo", "upgradeCopy"])
                ?? modelObject.string(at: ["upgradeCopy"])
        )

        let metadata = ModelCatalogMetadata(
            availabilityMessage: availabilityMessage,
            upgradeTargetModelID: upgradeTarget,
            upgradeMessage: upgradeMessage
        )
        return metadata.isEmpty ? nil : metadata
    }

    private nonisolated static func parseSupportedReasoningEfforts(from modelObject: [String: JSONValue]) -> [ReasoningEffort] {
        guard let supported = modelObject.array(at: ["supportedReasoningEfforts"]) else {
            return []
        }

        var efforts = OrderedSet<ReasoningEffort>()
        for item in supported {
            if let effort = parseReasoningEffort(item.stringValue) {
                efforts.append(effort)
                continue
            }

            if let object = item.objectValue {
                let value = object.string(at: ["reasoningEffort"]) ?? object.string(at: ["effort"])
                if let effort = parseReasoningEffort(value) {
                    efforts.append(effort)
                }
            }
        }

        return Array(efforts)
    }

    private nonisolated static func parseReasoningEffort(_ raw: String?) -> ReasoningEffort? {
        guard let raw else { return nil }
        return ReasoningEffort(rawValue: raw.lowercased())
    }
}
