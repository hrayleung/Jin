import Foundation

extension VertexAIRequestBuilder {
    func makeRequestBody(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition]
    ) throws -> [String: Any] {
        let supportsNativePDF = supportsNativePDF(modelID: modelID, controls: controls)
        var body: [String: Any] = [
            "contents": try translatedMessages(messages, supportsNativePDF: supportsNativePDF),
            "generationConfig": makeGenerationConfig(controls, modelID: modelID)
        ]

        let explicitCachedContent = explicitCachedContentName(from: controls)
        if let cachedContent = explicitCachedContent {
            body["cachedContent"] = cachedContent
        } else if let systemInstruction = systemInstruction(from: messages) {
            body["systemInstruction"] = systemInstruction
        }

        let toolArray = makeTools(modelID: modelID, controls: controls, tools: tools)
        if !toolArray.isEmpty {
            body["tools"] = toolArray
        }

        if let toolConfig = makeToolConfig(modelID: modelID, controls: controls) {
            body["toolConfig"] = toolConfig
        }

        return body
    }

    func translatedMessages(
        _ messages: [Message],
        supportsNativePDF: Bool
    ) throws -> [[String: Any]] {
        try VertexAIMessageTranslation.translateMessages(
            messages,
            supportsNativePDF: supportsNativePDF
        )
    }

    func systemInstruction(from messages: [Message]) -> [String: Any]? {
        let parts = messages
            .filter { $0.role == .system }
            .flatMap(\.content)
            .compactMap { part -> String? in
                guard case .text(let text) = part else { return nil }
                return text.trimmedNonEmpty == nil ? nil : text
            }
            .map { ["text": $0] }

        guard !parts.isEmpty else { return nil }
        return ["parts": parts]
    }

    func explicitCachedContentName(from controls: GenerationControls) -> String? {
        guard controls.contextCache?.mode == .explicit else { return nil }
        return normalizedTrimmedString(controls.contextCache?.cachedContentName)
    }

    func supportsNativePDF(modelID: String, controls: GenerationControls) -> Bool {
        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        return allowNativePDF && modelSupport.supportsNativePDF(modelID)
    }
}
