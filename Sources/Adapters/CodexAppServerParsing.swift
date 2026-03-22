import Collections
import Foundation
import Network

// MARK: - Model Info Parsing, Agent Message Text, Dynamic Tool Call Output, Connectivity Errors

extension CodexAppServerAdapter {

    // MARK: - Model Info Parsing

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

    // MARK: - Dynamic Tool Call Output

    nonisolated static func parseDynamicToolCallOutputParts(
        from item: [String: JSONValue]
    ) -> [ContentPart] {
        guard let contentItems = item.array(at: ["contentItems"]), !contentItems.isEmpty else {
            return []
        }

        var parts: [ContentPart] = []
        parts.reserveCapacity(contentItems.count)

        for contentItem in contentItems {
            guard let object = contentItem.objectValue else { continue }
            let type = object.string(at: ["type"])?.lowercased()
            switch type {
            case "inputtext", "input_text":
                if let text = trimmedValue(object.string(at: ["text"])), !text.isEmpty {
                    parts.append(.text(text))
                }
            case "inputimage", "input_image":
                let rawURL = trimmedValue(object.string(at: ["imageUrl"]) ?? object.string(at: ["image_url"]))
                if let rawURL, let url = URL(string: rawURL) {
                    parts.append(.image(ImageContent(mimeType: "image/png", url: url, assetDisposition: .externalReference)))
                }
            default:
                break
            }
        }

        return parts
    }

    // MARK: - Agent Message Text

    nonisolated static func parseAgentMessageText(from item: [String: JSONValue]) -> String? {
        let root = JSONValue.object(item)
        let collected = collectAgentMessageTextFragments(from: root)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collected.isEmpty ? nil : collected
    }

    nonisolated static func assistantTextSuffix(fromSnapshot snapshot: String, emitted: String) -> String? {
        guard !snapshot.isEmpty else { return nil }
        if emitted.isEmpty {
            return snapshot
        }
        if snapshot == emitted {
            return nil
        }
        if snapshot.hasPrefix(emitted) {
            let index = snapshot.index(snapshot.startIndex, offsetBy: emitted.count)
            let suffix = String(snapshot[index...])
            return suffix.isEmpty ? nil : suffix
        }
        if emitted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return snapshot
        }
        return nil
    }

    nonisolated static func collectAgentMessageTextFragments(from value: JSONValue) -> [String] {
        switch value {
        case .string(let text):
            return [text]

        case .array(let array):
            return array.flatMap { collectAgentMessageTextFragments(from: $0) }

        case .object(let object):
            var fragments: [String] = []

            if let text = object.string(at: ["text"]) {
                fragments.append(text)
            }
            if let valueText = object.string(at: ["value"]),
               object.string(at: ["type"]) == "output_text" || object.string(at: ["type"]) == "text" {
                fragments.append(valueText)
            }

            for key in ["message", "content", "contentItems", "output", "parts", "item"] {
                guard let nested = object[key] else { continue }
                fragments.append(contentsOf: collectAgentMessageTextFragments(from: nested))
            }
            return fragments

        default:
            return []
        }
    }

    // MARK: - Connectivity Error Handling

    nonisolated static func remapCodexConnectivityError(_ error: Error, endpoint: URL) -> Error {
        guard let guidance = codexConnectivityGuidanceMessage(for: error, endpoint: endpoint) else {
            return error
        }
        return LLMError.providerError(code: "codex_server_unavailable", message: guidance)
    }

    nonisolated static func codexConnectivityGuidanceMessage(
        for error: Error,
        endpoint: URL
    ) -> String? {
        guard isLikelyCodexServerUnavailable(error) else { return nil }
        let endpointString = endpoint.absoluteString
        return """
        Cannot connect to Codex App Server at \(endpointString).

        If you're using a local server, start it first:
        - Jin -> Settings -> Providers -> Codex App Server (Beta) -> Start Server
        - Terminal: codex app-server --listen \(endpointString)

        If you're using a remote endpoint, verify the URL/network and retry.
        """
    }

    // MARK: - Catalog Metadata & Reasoning Efforts

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

    // MARK: - General Utility Helpers

    nonisolated static func firstPositiveInt(
        from object: [String: JSONValue],
        candidatePaths: [[String]]
    ) -> Int? {
        for path in candidatePaths {
            if let value = object.int(at: path), value > 0 {
                return value
            }
        }
        return nil
    }

    nonisolated static func trimmedValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func jsonValueToAny(_ value: JSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let b):
            return b
        case .number(let n):
            return n
        case .string(let s):
            return s
        case .array(let arr):
            return arr.map { jsonValueToAny($0) }
        case .object(let obj):
            return obj.mapValues { jsonValueToAny($0) }
        }
    }

    // MARK: - Connectivity Detection (Private)

    private nonisolated static func isLikelyCodexServerUnavailable(_ error: Error) -> Bool {
        if case LLMError.invalidRequest(let message) = error,
           message.localizedCaseInsensitiveContains("not connected") {
            return true
        }

        guard case LLMError.networkError(let underlying) = error else {
            return false
        }

        if isLikelyConnectionPOSIXError(underlying) {
            return true
        }

        let description = underlying.localizedDescription.lowercased()
        let connectivityHints = [
            "connection refused",
            "failed to connect",
            "timed out",
            "network is unreachable",
            "host is down",
            "socket is not connected",
            "websocket connection was cancelled",
            "connection reset",
            "connection aborted",
            "broken pipe",
        ]
        return connectivityHints.contains { description.contains($0) }
    }

    private nonisolated static func isLikelyConnectionPOSIXError(_ error: Error) -> Bool {
        if let nwError = error as? NWError {
            switch nwError {
            case .posix(let code):
                return isLikelyConnectionPOSIXCode(Int32(code.rawValue))
            case .dns:
                return true
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return isLikelyConnectionPOSIXCode(Int32(nsError.code))
        }
        return false
    }

    private nonisolated static func isLikelyConnectionPOSIXCode(_ code: Int32) -> Bool {
        code == ECONNREFUSED
            || code == ETIMEDOUT
            || code == EHOSTUNREACH
            || code == ENETUNREACH
            || code == EHOSTDOWN
            || code == ECONNRESET
            || code == ECONNABORTED
            || code == EPIPE
    }
}
