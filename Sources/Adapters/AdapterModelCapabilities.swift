import Foundation

// MARK: - Model Lookup

/// Finds a model in the provider config by exact ID, with case-insensitive fallback.
func findConfiguredModel(in providerConfig: ProviderConfig, for modelID: String) -> ModelInfo? {
    ProviderModelAliasResolver.resolvedModel(
        for: modelID,
        providerType: providerConfig.type,
        availableModels: providerConfig.models
    )
}

// MARK: - Web Search Support Detection

/// Checks whether a model supports web search based on configured model info or capability registry.
/// This is the shared implementation used by all adapters that duplicate this logic.
func modelSupportsWebSearch(
    providerConfig: ProviderConfig,
    modelID: String
) -> Bool {
    if let resolved = resolvedConfiguredModelSettings(providerConfig: providerConfig, modelID: modelID) {
        return resolved.supportsWebSearch
    }

    return ModelCapabilityRegistry.supportsWebSearch(
        for: providerConfig.type,
        modelID: modelID
    )
}

// MARK: - Reasoning Support Detection

/// Checks whether a model supports video input based on configured model info or the catalog.
/// Exact catalog `.videoInput` only — never inferred from a video-like modality string.
func modelSupportsVideoInput(
    providerConfig: ProviderConfig,
    modelID: String
) -> Bool {
    if let resolved = resolvedConfiguredModelSettings(providerConfig: providerConfig, modelID: modelID) {
        return resolved.capabilities.contains(.videoInput)
    }

    return ModelCatalog.entry(for: modelID, provider: providerConfig.type)?
        .capabilities.contains(.videoInput) == true
}

/// Checks whether a model supports reasoning based on configured model info or capability registry.
func modelSupportsReasoning(
    providerConfig: ProviderConfig,
    modelID: String
) -> Bool {
    if let resolved = resolvedConfiguredModelSettings(providerConfig: providerConfig, modelID: modelID) {
        return supportsReasoning(resolvedModelSettings: resolved)
    }

    return supportsReasoning(
        reasoningConfig: catalogReasoningConfig(providerConfig: providerConfig, modelID: modelID)
    )
}

private func resolvedConfiguredModelSettings(
    providerConfig: ProviderConfig,
    modelID: String
) -> ResolvedModelSettings? {
    guard let model = findConfiguredModel(in: providerConfig, for: modelID) else {
        return nil
    }

    return ModelSettingsResolver.resolve(model: model, providerType: providerConfig.type)
}

private func catalogReasoningConfig(
    providerConfig: ProviderConfig,
    modelID: String
) -> ModelReasoningConfig? {
    if let catalogEntry = ModelCatalog.entry(for: modelID, provider: providerConfig.type) {
        guard catalogEntry.capabilities.contains(.reasoning) else { return nil }
        return catalogEntry.reasoningConfig
    }

    return ModelCapabilityRegistry.defaultReasoningConfig(
        for: providerConfig.type,
        modelID: modelID
    )
}

private func supportsReasoning(resolvedModelSettings: ResolvedModelSettings) -> Bool {
    guard resolvedModelSettings.capabilities.contains(.reasoning) else { return false }
    return supportsReasoning(reasoningConfig: resolvedModelSettings.reasoningConfig)
}

private func supportsReasoning(reasoningConfig: ModelReasoningConfig?) -> Bool {
    guard let reasoningConfig else { return false }
    return reasoningConfig.type != .none
}

// MARK: - Base URL Normalization

/// Strips a trailing `/v1` suffix from a base URL, returning the root.
/// Useful for providers where users may paste a URL with or without the version path.
func stripTrailingV1(_ rawURL: String) -> String {
    let trimmed = rawURL.hasSuffix("/") ? String(rawURL.dropLast()) : rawURL

    if trimmed.hasSuffix("/v1") {
        let withoutV1 = String(trimmed.dropLast(3))
        return withoutV1.hasSuffix("/") ? String(withoutV1.dropLast()) : withoutV1
    }

    return trimmed
}

// MARK: - Reasoning Effort String Mapping

/// Maps a `ReasoningEffort` to the wire string used by providers whose API accepts
/// `low`, `medium`, or `high`, with an explicit `none` option to disable reasoning.
///
/// `.none` → `"none"`, `.minimal`/`.low` → `"low"`, `.medium` → `"medium"`,
/// `.high`/`.xhigh`/`.max` → `"high"`.
///
/// Used by Fireworks and OpenCodeGo adapters.
func mapReasoningEffortNoneDisabled(_ effort: ReasoningEffort) -> String {
    switch effort {
    case .none:
        return "none"
    case .minimal, .low:
        return "low"
    case .medium:
        return "medium"
    case .high, .xhigh, .max:
        return "high"
    }
}

/// Maps a `ReasoningEffort` to the wire string used by providers that always use at
/// least `low` (i.e. `.none` is treated as `"low"` rather than disabling reasoning).
///
/// `.none`/`.minimal`/`.low` → `"low"`, `.medium` → `"medium"`,
/// `.high`/`.xhigh`/`.max` → `"high"`.
///
/// Used by SambaNova and xAI adapters.
func mapReasoningEffortNoneAsLow(_ effort: ReasoningEffort) -> String {
    switch effort {
    case .none, .minimal, .low:
        return "low"
    case .medium:
        return "medium"
    case .high, .xhigh, .max:
        return "high"
    }
}

// MARK: - Audio Model ID Detection

/// Detects whether a model ID (lowercased) supports audio input.
/// Shared across OpenAICompatibleAdapter and OpenRouterAdapter.
func isAudioInputModelID(_ lowerModelID: String) -> Bool {
    if lowerModelID.contains("gpt-audio")
        || lowerModelID.contains("audio-preview")
        || lowerModelID.contains("realtime")
        || lowerModelID.contains("voxtral")
        || lowerModelID.contains("qwen3-asr")
        || lowerModelID.contains("qwen3-omni") {
        return true
    }

    if (lowerModelID.contains("gemini-2.5") || lowerModelID.contains("gemini-3") || lowerModelID.contains("gemini-2.0"))
        && !lowerModelID.contains("-image")
        && !lowerModelID.contains("imagen") {
        return true
    }

    return false
}

// MARK: - Fireworks Model ID Utilities

private let fireworksMiniMaxM2CanonicalIDs: Set<String> = [
    "minimax-m2", "minimax-m2p1", "minimax-m2p5", "minimax-m2p7"
]

let fireworksDeepSeekV4ProAccountModelID = "accounts/fireworks/models/deepseek-v4-pro"
let fireworksDeepSeekV4ProCatalogModelID = "deepseek-ai/deepseek-v4-pro"
let fireworksDeepSeekV4ProPreferredModelIDs = [
    fireworksDeepSeekV4ProAccountModelID,
    fireworksDeepSeekV4ProCatalogModelID,
]
let fireworksDeepSeekV4ProModelIDs = Set(fireworksDeepSeekV4ProPreferredModelIDs)
let fireworksDeepSeekV4Pro0813PreferredModelIDs = [
    "accounts/fireworks/models/deepseek-v4-pro-0813",
    "fireworks/deepseek-v4-pro-0813",
    "deepseek-ai/deepseek-v4-pro-0813",
]

/// Extracts the canonical (lowercased, prefix-stripped) Fireworks model ID.
/// Returns nil if the model ID contains an unrecognized namespace prefix.
func fireworksCanonicalModelID(_ modelID: String) -> String? {
    let lower = modelID.lowercased()
    if lower.hasPrefix("fireworks/") {
        return String(lower.dropFirst("fireworks/".count))
    }
    if lower.hasPrefix("accounts/fireworks/models/") {
        return String(lower.dropFirst("accounts/fireworks/models/".count))
    }
    if !lower.contains("/") {
        return lower
    }
    return nil
}

/// Checks whether a Fireworks model ID belongs to the MiniMax M2 family.
func isFireworksMiniMaxM2FamilyModel(_ modelID: String) -> Bool {
    guard let canonical = fireworksCanonicalModelID(modelID) else { return false }
    return fireworksMiniMaxM2CanonicalIDs.contains(canonical)
}

/// Checks exact Fireworks IDs verified for DeepSeek V4 Pro support.
func isFireworksDeepSeekV4ProModel(_ modelID: String) -> Bool {
    fireworksDeepSeekV4ProModelIDs.contains(modelID.lowercased())
}

/// Fireworks GLM-5.3 / GLM-5.3 Fast / GLM-5.3-Flash. Official Z.ai GLM-5.3
/// and GLM-5.3-Flash reject `thinking.type: disabled`; Off maps to
/// `reasoning_effort: low`.
func isFireworksGLM53Model(_ modelID: String) -> Bool {
    let lower = modelID.lowercased()
    if lower == "accounts/fireworks/models/glm-5p3"
        || lower == "fireworks/glm-5p3"
        || lower == "accounts/fireworks/routers/glm-5p3-fast"
        || lower == "fireworks/glm-5p3-fast"
        || lower == "accounts/fireworks/models/glm-5p3-flash"
        || lower == "fireworks/glm-5p3-flash" {
        return true
    }
    guard let canonical = fireworksCanonicalModelID(lower) else { return false }
    return canonical == "glm-5p3" || canonical == "glm-5p3-fast" || canonical == "glm-5p3-flash"
}

/// Fireworks DeepSeek V4 GA snapshots (`0813`, `flash-0731`). Enabled turns send
/// top-level `reasoning_effort` low/high/max (no `thinking` object). Disabled
/// turns use the official DeepSeek `thinking: {type: disabled}` envelope — not
/// `reasoning_effort: none`, which is outside the GA band.
func isFireworksDeepSeekV4GAModel(_ modelID: String) -> Bool {
    let lower = modelID.lowercased()
    if fireworksDeepSeekV4Pro0813PreferredModelIDs.contains(lower)
        || lower == "accounts/fireworks/models/deepseek-v4-flash-0731"
        || lower == "fireworks/deepseek-v4-flash-0731" {
        return true
    }
    guard let canonical = fireworksCanonicalModelID(lower) else { return false }
    return canonical == "deepseek-v4-pro-0813" || canonical == "deepseek-v4-flash-0731"
}

// MARK: - OpenAI Responses API Supported File MIME Types

/// MIME types supported natively by the OpenAI Responses API via `input_file`.
/// Shared by `OpenAIAdapter` and `OpenAIWebSocketAdapter`.
let openAISupportedFileMIMETypes: Set<String> = [
    "application/pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document", // docx
    "application/msword",                                                        // doc
    "application/vnd.oasis.opendocument.text",                                  // odt
    "application/rtf", "text/rtf",                                              // rtf
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",        // xlsx
    "application/vnd.ms-excel",                                                 // xls
    "text/csv",                                                                 // csv
    "text/tab-separated-values",                                                // tsv
    "application/vnd.openxmlformats-officedocument.presentationml.presentation", // pptx
    "application/vnd.ms-powerpoint",                                            // ppt
    "text/plain",                                                               // txt
    "text/markdown", "text/x-markdown",                                        // md
    "application/json",                                                         // json
    "text/html",                                                                // html
    "application/xml", "text/xml",                                              // xml
]

private let googleSpreadsheetMIMETypes: Set<String> = [
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.ms-excel"
]

func googleFileFallbackText(_ file: FileContent, providerName: String) -> String {
    let base = AttachmentPromptRenderer.fallbackText(for: file)
    let mimeType = normalizedMIMEType(file.mimeType)
    let hasExtractedText = file.extractedText?.trimmedNonEmpty != nil

    guard googleSpreadsheetMIMETypes.contains(mimeType) || hasExtractedText else {
        return base
    }

    let note: String
    if googleSpreadsheetMIMETypes.contains(mimeType) {
        note = "\(providerName) does not provide .xlsx/.xls attachments as mounted local files in Jin. Use extracted contents instead of opening the original filename from Python."
    } else {
        note = "\(providerName) received extracted document contents, not a mounted local file. Do not open the original filename from Python."
    }

    return """
Attachment access note: \(note)

\(base)
"""
}

// MARK: - OpenAI Audio Model ID Detection

/// Audio input model IDs specific to OpenAI's first-party models.
/// Shared by `OpenAIAdapter` and `OpenAIWebSocketAdapter`.
private let openAIAudioInputModelIDs: Set<String> = [
    "gpt-4o-audio-preview",
    "gpt-4o-audio-preview-2024-10-01",
    "gpt-4o-mini-audio-preview",
    "gpt-4o-mini-audio-preview-2024-12-17",
    "gpt-4o-realtime-preview",
    "gpt-4o-realtime-preview-2024-10-01",
    "gpt-4o-realtime-preview-2024-12-17",
    "gpt-4o-mini-realtime-preview",
    "gpt-4o-mini-realtime-preview-2024-12-17",
    "gpt-realtime",
    "gpt-realtime-mini",
]

/// Checks whether an OpenAI model ID (lowercased) supports audio input.
func isOpenAIAudioInputModelID(_ lowerModelID: String) -> Bool {
    openAIAudioInputModelIDs.contains(lowerModelID)
}

// MARK: - OpenAI Responses Sampling Parameter Support

/// GPT-5 family models generally reject `temperature` / `top_p` on Responses API.
/// Per current OpenAI docs, GPT-5.2-and-newer models only accept these when reasoning is `none`,
/// while older GPT-5 models do not support them on Responses at all.
/// Keep this conservative to avoid `400 invalid_request_error` for unsupported models.
private let openAIResponsesSamplingAllowedModelIDs: Set<String> = [
    "gpt-5.4",
    "gpt-5.4-2026-03-05",
    "gpt-5.4-pro",
    "gpt-5.4-pro-2026-03-05",
    "gpt-5.4-mini",
    "gpt-5.4-mini-2026-03-17",
    "gpt-5.4-nano",
    "gpt-5.4-nano-2026-03-17",
    "gpt-5.2",
    "gpt-5.2-2025-12-11",
    "gpt-5.1",
]

/// GPT-5.6 Daybreak aliases whose IDs do not contain `gpt-5`.
/// Exact IDs only — they share Sol/Cyber's Responses sampling rejection.
private let openAIResponsesSamplingDeniedExactModelIDs: Set<String> = [
    "gpt-daybreak-red-latest",
    "gpt-daybreak-blue-latest",
]

func supportsOpenAIResponsesSamplingParameters(
    modelID: String,
    reasoningEnabled: Bool,
    providerType: ProviderType? = nil
) -> Bool {
    // Router relays one Responses payload to whichever upstream serves the model, so
    // Anthropic's own rule leaks through: "`temperature` may only be set to 1 when
    // thinking is enabled." That is invisible from the model ID's shape alone, hence
    // the provider hint (verified against the live gateway 2026-08-22).
    if RouterRequestSupport.suppressesSamplingParameters(
        providerType: providerType,
        modelID: modelID,
        reasoningEnabled: reasoningEnabled
    ) {
        return false
    }

    let lower = modelID.lowercased()
    let canonical: String
    if lower.hasPrefix("openai/") {
        canonical = String(lower.dropFirst("openai/".count))
    } else {
        canonical = lower
    }

    if openAIResponsesSamplingDeniedExactModelIDs.contains(canonical) {
        return false
    }

    // Preserve prior behavior for non-GPT-5 models.
    guard canonical.contains("gpt-5") else {
        return true
    }

    guard !reasoningEnabled else {
        return false
    }

    return openAIResponsesSamplingAllowedModelIDs.contains(canonical)
}

// MARK: - OpenAI Service Tier Support

/// Resolves OpenAI `service_tier` from structured controls, with legacy fallback.
///
/// Legacy fallback keeps compatibility with older persisted `providerSpecific["service_tier"]`.
func resolvedOpenAIServiceTier(from controls: GenerationControls) -> String? {
    if let serviceTier = controls.openAIServiceTier {
        return serviceTier.rawValue
    }

    let legacyRaw = controls.providerSpecific["service_tier"]?.value as? String
    return OpenAIServiceTier.normalized(rawValue: legacyRaw)?.rawValue
}

// MARK: - OpenAI-Compatible Streaming Dispatch

/// Common send/stream dispatch for OpenAI Chat Completions-compatible adapters.
/// Eliminates the identical streaming/non-streaming branching duplicated in
/// DeepSeek, Cerebras, Fireworks, Perplexity, OpenRouter, and OpenAICompatible adapters.
func sendOpenAICompatibleMessage(
    request: URLRequest,
    streaming: Bool,
    reasoningField: OpenAIChatCompletionsReasoningField,
    networkManager: NetworkManager
) async throws -> AsyncThrowingStream<StreamEvent, Error> {
    if !streaming {
        let (data, _) = try await networkManager.sendRequest(request)
        let response = try OpenAIChatCompletionsCore.decodeResponse(data)
        return OpenAIChatCompletionsCore.makeNonStreamingStream(
            response: response,
            reasoningField: reasoningField
        )
    }

    let parser = SSEParser()
    let sseStream = await networkManager.streamRequest(request, parser: parser)
    return OpenAIChatCompletionsCore.makeStreamingStream(
        sseStream: sseStream,
        reasoningField: reasoningField
    )
}
