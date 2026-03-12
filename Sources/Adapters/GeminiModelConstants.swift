import Foundation

/// Shared model-family identification constants used by both `GeminiAdapter`
/// and `VertexAIAdapter`. Centralizes the sets so they stay in sync when new
/// models are added.
enum GeminiModelConstants {

    /// All known Gemini model IDs (lowercased) used for capability inference.
    static let knownModelIDs: Set<String> = [
        "gemini-3",
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro-preview",
        "gemini-3.1-flash-image-preview",
        "gemini-3.1-flash-lite-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image-preview",
        "gemini-2.5",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-flash-image",
        "gemini-2.0-flash",
        "gemini-2.0-flash-lite",
    ]

    /// Gemini 3 family models (lowercased).
    static let gemini3ModelIDs: Set<String> = [
        "gemini-3",
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro-preview",
        "gemini-3.1-flash-image-preview",
        "gemini-3.1-flash-lite-preview",
        "gemini-3-flash-preview",
        "gemini-3-pro-image-preview",
    ]

    /// Gemini models that support native image generation (lowercased).
    static let imageGenerationModelIDs: Set<String> = [
        "gemini-3-pro-image-preview",
        "gemini-3.1-flash-image-preview",
        "gemini-2.5-flash-image",
    ]

    /// Gemini 2.5 text-only models (lowercased). Used to suppress certain
    /// VertexAI generation config fields (e.g., `thinkingLevel`).
    static let gemini25TextModelIDs: Set<String> = [
        "gemini-2.5",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
    ]

    /// Models that accept native PDF via `inlineData` (lowercased).
    /// Gemini 3 family models, plus Gemini 2.5 text models for Vertex.
    static let nativePDFModelIDs: Set<String> = [
        "gemini-3",
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3.1-flash-image-preview",
        "gemini-3.1-flash-lite-preview",
    ]

    /// Extended native PDF set for Vertex AI, which also supports Gemini 2.5 family.
    static let vertexNativePDFModelIDs: Set<String> = {
        nativePDFModelIDs.union(gemini25TextModelIDs)
    }()

    // MARK: - Query Helpers

    static func isKnownModel(_ modelID: String) -> Bool {
        knownModelIDs.contains(modelID.lowercased())
    }

    static func isGemini3Model(_ modelID: String) -> Bool {
        gemini3ModelIDs.contains(modelID.lowercased())
    }

    static func isImageGenerationModel(_ modelID: String) -> Bool {
        imageGenerationModelIDs.contains(modelID.lowercased())
    }

    static func isGemini25TextModel(_ modelID: String) -> Bool {
        gemini25TextModelIDs.contains(modelID.lowercased())
    }

    static func supportsNativePDF(_ modelID: String) -> Bool {
        nativePDFModelIDs.contains(modelID.lowercased())
    }

    static func supportsVertexNativePDF(_ modelID: String) -> Bool {
        vertexNativePDFModelIDs.contains(modelID.lowercased())
    }

    /// Maps a `ReasoningEffort` to a Google thinking level string.
    /// Shared by both GeminiAdapter and VertexAIAdapter.
    static func mapEffortToThinkingLevel(
        _ effort: ReasoningEffort,
        for providerType: ProviderType,
        modelID: String
    ) -> String {
        let supportedEfforts = ModelCapabilityRegistry.supportedReasoningEfforts(
            for: providerType,
            modelID: modelID
        )
        let supportsMinimal = supportedEfforts.contains(.minimal)
        let supportsMedium = supportedEfforts.contains(.medium)

        switch effort {
        case .none, .minimal:
            return supportsMinimal ? "MINIMAL" : "LOW"
        case .low:
            return "LOW"
        case .medium:
            return supportsMedium ? "MEDIUM" : "HIGH"
        case .high, .xhigh:
            return "HIGH"
        }
    }

    /// Returns the default thinking level when reasoning is off.
    static func defaultThinkingLevelWhenOff(
        for providerType: ProviderType,
        modelID: String
    ) -> String {
        let supportsMinimal = ModelCapabilityRegistry.supportedReasoningEfforts(
            for: providerType,
            modelID: modelID
        ).contains(.minimal)
        return supportsMinimal ? "MINIMAL" : "LOW"
    }

    struct GoogleCodeExecutionEventState {
        fileprivate var nextOrdinal = 0
        fileprivate var activeExecutionID: String?
        fileprivate var currentExecutionHasResult = false

        init() {}

        fileprivate mutating func executionIDForCodePart() -> String {
            if activeExecutionID == nil || currentExecutionHasResult {
                activeExecutionID = "google-code-execution-\(nextOrdinal)"
                nextOrdinal += 1
                currentExecutionHasResult = false
            }

            return activeExecutionID ?? "google-code-execution-unknown"
        }

        fileprivate mutating func executionIDForResultPart() -> String {
            if activeExecutionID == nil {
                activeExecutionID = "google-code-execution-\(nextOrdinal)"
                nextOrdinal += 1
            }
            currentExecutionHasResult = true
            return activeExecutionID ?? "google-code-execution-unknown"
        }
    }

    /// Converts a single Google `Part` response into domain `StreamEvent`s.
    /// Shared by both GeminiAdapter and VertexAIAdapter stream parsing.
    static func events(from part: GoogleGenerateContentResponse.Part) -> [StreamEvent] {
        var codeExecutionState = GoogleCodeExecutionEventState()
        return events(from: [part], codeExecutionState: &codeExecutionState)
    }

    static func events(
        from parts: [GoogleGenerateContentResponse.Part],
        codeExecutionState: inout GoogleCodeExecutionEventState
    ) -> [StreamEvent] {
        var out: [StreamEvent] = []

        for part in parts {
            out.append(contentsOf: events(from: part, codeExecutionState: &codeExecutionState))
        }

        return out
    }

    private static func events(
        from part: GoogleGenerateContentResponse.Part,
        codeExecutionState: inout GoogleCodeExecutionEventState
    ) -> [StreamEvent] {
        var out: [StreamEvent] = []

        if part.thought == true {
            let text = part.text ?? ""
            let signature = part.thoughtSignature
            if !text.isEmpty || signature != nil {
                out.append(.thinkingDelta(.thinking(textDelta: text, signature: signature)))
            }
        } else if let text = part.text, !text.isEmpty {
            out.append(.contentDelta(.text(text)))
        }

        if let inline = part.inlineData,
           let base64 = inline.data,
           let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
            let mimeType = inline.mimeType ?? "image/png"
            if mimeType.lowercased().hasPrefix("image/") {
                out.append(.contentDelta(.image(ImageContent(mimeType: mimeType, data: data))))
            }
        }

        if let executableCode = part.executableCode,
           let code = normalizedGoogleCodeExecutionText(executableCode.code) {
            let id = codeExecutionState.executionIDForCodePart()
            out.append(.codeExecutionActivity(CodeExecutionActivity(
                id: id,
                status: .writingCode,
                code: code
            )))
        }

        if let result = part.codeExecutionResult {
            let id = codeExecutionState.executionIDForResultPart()
            let status = googleCodeExecutionStatus(for: result.outcome)
            let output = normalizedGoogleCodeExecutionText(result.output)

            let activity: CodeExecutionActivity
            switch status {
            case .failed:
                activity = CodeExecutionActivity(
                    id: id,
                    status: status,
                    stderr: output
                )
            default:
                activity = CodeExecutionActivity(
                    id: id,
                    status: status,
                    stdout: output
                )
            }

            out.append(.codeExecutionActivity(activity))
        }

        if let functionCall = part.functionCall {
            let toolCall = ToolCall(
                id: UUID().uuidString,
                name: functionCall.name,
                arguments: functionCall.args ?? [:],
                signature: part.thoughtSignature
            )
            out.append(.toolCallStart(toolCall))
            out.append(.toolCallEnd(toolCall))
        }

        return out
    }

    private static func normalizedGoogleCodeExecutionText(_ text: String?) -> String? {
        guard let text else { return nil }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized.isEmpty ? nil : normalized
    }

    private static func googleCodeExecutionStatus(for outcome: String?) -> CodeExecutionStatus {
        let normalized = (outcome ?? "OUTCOME_OK").uppercased()

        switch normalized {
        case "OUTCOME_OK", "OK", "SUCCESS":
            return .completed
        case "OUTCOME_FAILED", "FAILED", "ERROR":
            return .failed
        case "OUTCOME_DEADLINE_EXCEEDED", "DEADLINE_EXCEEDED", "TIMEOUT", "OUTCOME_CANCELLED", "CANCELLED":
            return .incomplete
        default:
            return .unknown(normalized.lowercased())
        }
    }

    /// Converts a Google grounding metadata to the shared grounding format.
    static func toSharedGrounding(_ g: GoogleGenerateContentResponse.GroundingMetadata) -> GoogleGroundingSearchActivities.GroundingMetadata {
        GoogleGroundingSearchActivities.GroundingMetadata(
            webSearchQueries: g.webSearchQueries,
            retrievalQueries: g.retrievalQueries,
            groundingChunks: g.groundingChunks?.map {
                .init(webURI: $0.web?.uri, webTitle: $0.web?.title)
            },
            groundingSupports: g.groundingSupports?.map {
                .init(segmentText: $0.segment?.text, groundingChunkIndices: $0.groundingChunkIndices)
            },
            searchEntryPoint: g.searchEntryPoint.map {
                .init(sdkBlob: $0.sdkBlob)
            }
        )
    }

    /// Builds a Google `inlineData` part from raw data or a file URL.
    /// Shared by both GeminiAdapter and VertexAIAdapter content translation.
    static func inlineDataPart(mimeType: String, data: Data?, url: URL?) throws -> [String: Any]? {
        if let data {
            return [
                "inlineData": [
                    "mimeType": mimeType,
                    "data": data.base64EncodedString()
                ]
            ]
        }

        if let url, url.isFileURL {
            let data = try resolveFileData(from: url)
            return [
                "inlineData": [
                    "mimeType": mimeType,
                    "data": data.base64EncodedString()
                ]
            ]
        }

        return nil
    }
}
