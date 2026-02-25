import Foundation
import CryptoKit

actor AutomaticExplicitCacheRegistry {
    static let shared = AutomaticExplicitCacheRegistry()

    private struct Entry: Sendable {
        let name: String
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]

    func cachedName(for key: String, now: Date = Date()) -> String? {
        if let entry = entries[key], entry.expiresAt > now {
            return entry.name
        }
        entries.removeValue(forKey: key)
        return nil
    }

    func save(name: String, for key: String, ttlSeconds: TimeInterval, now: Date = Date()) {
        entries[key] = Entry(name: name, expiresAt: now.addingTimeInterval(max(60, ttlSeconds)))
    }
}

// MARK: - Context Cache Utilities

enum ContextCacheUtilities {

    static let automaticGoogleExplicitCacheTTLSeconds: TimeInterval = 3600
    static let automaticGoogleExplicitCacheMinTokenEstimate = 2048

    static func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func normalizedSystemPrompt(in messages: [Message]) -> String? {
        guard let systemMessage = messages.first(where: { $0.role == .system }) else {
            return nil
        }
        let text = systemMessage.content.compactMap { part -> String? in
            if case .text(let value) = part {
                return value
            }
            return nil
        }.joined(separator: "\n")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func approximateTokenEstimate(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return max(1, text.count / 4)
    }

    static func normalizedGeminiCachedContentModel(_ modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("models/") {
            return trimmed
        }
        return "models/\(trimmed)"
    }

    static func normalizedVertexCachedContentModel(_ modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("publishers/") {
            return trimmed
        }
        if trimmed.hasPrefix("models/") {
            return "publishers/google/\(trimmed)"
        }
        return "publishers/google/models/\(trimmed)"
    }

    static func automaticOpenAICacheKey(
        modelID: String,
        messages: [Message],
        tools: [ToolDefinition]
    ) -> String {
        let systemText = normalizedSystemPrompt(in: messages) ?? ""
        let toolSignature = tools
            .map { tool in
                "\(tool.name)|\(tool.description)|\((tool.parameters.required).joined(separator: ","))"
            }
            .sorted()
            .joined(separator: "\n")
        let digest = sha256Hex("openai|\(modelID)|\(systemText)|\(toolSignature)")
        return "jin-prefix-\(digest.prefix(24))"
    }

    static func applyExplicitGoogleCache(
        named cachedContentName: String,
        messages: [Message],
        controls: GenerationControls
    ) -> (messages: [Message], controls: GenerationControls)? {
        guard let systemIndex = messages.firstIndex(where: { $0.role == .system }) else {
            return nil
        }

        var adjustedMessages = messages
        adjustedMessages.remove(at: systemIndex)

        var adjustedControls = controls
        var contextCache = adjustedControls.contextCache ?? ContextCacheControls(mode: .explicit)
        contextCache.mode = .explicit
        contextCache.cachedContentName = cachedContentName
        contextCache.strategy = nil
        contextCache.ttl = nil
        contextCache.cacheKey = nil
        contextCache.conversationID = nil
        contextCache.minTokensThreshold = nil
        adjustedControls.contextCache = contextCache

        return (adjustedMessages, adjustedControls)
    }

    static func prepareGeminiExplicitContextCache(
        adapter: GeminiAdapter,
        modelID: String,
        messages: [Message],
        controls: GenerationControls
    ) async -> (messages: [Message], controls: GenerationControls)? {
        await prepareGoogleExplicitContextCache(
            providerPrefix: "gemini",
            normalizedModel: normalizedGeminiCachedContentModel(modelID),
            modelID: modelID,
            messages: messages,
            controls: controls,
            createCachedContent: { payload in
                try await adapter.createCachedContent(payload: payload).name
            }
        )
    }

    static func prepareVertexExplicitContextCache(
        adapter: VertexAIAdapter,
        modelID: String,
        messages: [Message],
        controls: GenerationControls
    ) async -> (messages: [Message], controls: GenerationControls)? {
        await prepareGoogleExplicitContextCache(
            providerPrefix: "vertex",
            normalizedModel: normalizedVertexCachedContentModel(modelID),
            modelID: modelID,
            messages: messages,
            controls: controls,
            createCachedContent: { payload in
                try await adapter.createCachedContent(payload: payload).name
            }
        )
    }

    /// Shared implementation for Gemini and Vertex AI explicit context cache preparation.
    private static func prepareGoogleExplicitContextCache(
        providerPrefix: String,
        normalizedModel: String,
        modelID: String,
        messages: [Message],
        controls: GenerationControls,
        createCachedContent: ([String: Any]) async throws -> String
    ) async -> (messages: [Message], controls: GenerationControls)? {
        guard let systemText = normalizedSystemPrompt(in: messages),
              approximateTokenEstimate(for: systemText) >= automaticGoogleExplicitCacheMinTokenEstimate else {
            return nil
        }

        let fingerprint = sha256Hex("\(providerPrefix)|\(modelID)|\(systemText)")
        let displayName = "jin-auto-\(fingerprint.prefix(24))"
        let registryKey = "\(providerPrefix)|\(modelID)|\(fingerprint)"

        let cachedName: String
        if let name = await AutomaticExplicitCacheRegistry.shared.cachedName(for: registryKey) {
            cachedName = name
        } else {
            let payload: [String: Any] = [
                "model": normalizedModel,
                "displayName": displayName,
                "ttl": "\(Int(automaticGoogleExplicitCacheTTLSeconds))s",
                "systemInstruction": [
                    "parts": [
                        ["text": systemText]
                    ]
                ]
            ]

            do {
                cachedName = try await createCachedContent(payload)
                await AutomaticExplicitCacheRegistry.shared.save(
                    name: cachedName,
                    for: registryKey,
                    ttlSeconds: automaticGoogleExplicitCacheTTLSeconds * 0.9
                )
            } catch {
                return nil
            }
        }

        return applyExplicitGoogleCache(named: cachedName, messages: messages, controls: controls)
    }

    static func applyAutomaticContextCacheOptimizations(
        adapter: any LLMProviderAdapter,
        providerType: ProviderType,
        modelID: String,
        messages: [Message],
        controls: GenerationControls,
        tools: [ToolDefinition]
    ) async -> (messages: [Message], controls: GenerationControls) {
        var adjustedMessages = messages
        var adjustedControls = controls

        guard adjustedControls.contextCache?.mode != .off else {
            return (adjustedMessages, adjustedControls)
        }

        switch providerType {
        case .openai:
            adjustedControls.contextCache?.cacheKey = automaticOpenAICacheKey(
                modelID: modelID,
                messages: messages,
                tools: tools
            )
        case .openaiWebSocket:
            adjustedControls.contextCache?.cacheKey = automaticOpenAICacheKey(
                modelID: modelID,
                messages: messages,
                tools: tools
            )
        case .anthropic:
            // Anthropic's top-level automatic cache keeps the cache window aligned
            // with the evolving conversation prefix.
            adjustedControls.contextCache?.strategy = .prefixWindow
        case .gemini:
            if let geminiAdapter = adapter as? GeminiAdapter,
               let prepared = await prepareGeminiExplicitContextCache(
                    adapter: geminiAdapter,
                    modelID: modelID,
                    messages: messages,
                    controls: adjustedControls
               ) {
                adjustedMessages = prepared.messages
                adjustedControls = prepared.controls
            }
        case .vertexai:
            if let vertexAdapter = adapter as? VertexAIAdapter,
               let prepared = await prepareVertexExplicitContextCache(
                    adapter: vertexAdapter,
                    modelID: modelID,
                    messages: messages,
                    controls: adjustedControls
               ) {
                adjustedMessages = prepared.messages
                adjustedControls = prepared.controls
            }
        case .xai, .codexAppServer, .openaiCompatible, .cloudflareAIGateway, .openrouter, .perplexity, .groq, .cohere, .mistral, .deepinfra, .deepseek, .fireworks, .cerebras:
            break
        }

        return (adjustedMessages, adjustedControls)
    }
}
