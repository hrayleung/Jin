import Foundation

/// Exact-ID classification for Makora's vLLM OpenAI-compatible API.
///
/// Sources:
/// - https://www.makora.com (current lineup + context cards)
/// - https://inference.makora.com/v1 (unified Chat Completions + `/models`)
/// - omp-makora-provider 1.0.4 `models.json` (live `/v1/models` dump) + `patch.json`
/// - Respan gateway pages under `/models/makora/…` (exact IDs + modalities)
enum MakoraModelSupport {
    static let unifiedBaseURL = "https://inference.makora.com/v1"
    static let llamaFP8SlugBaseURL = "https://inference.makora.com/llama3-3-70b-instruct-fp8/v1"

    static let deepSeekV4FlashID = "deepseek-ai/DeepSeek-V4-Flash"
    static let deepSeekV4Flash0731ID = "deepseek-ai/DeepSeek-V4-Flash-0731"
    static let deepSeekV4ProID = "deepseek-ai/DeepSeek-V4-Pro"
    static let gemma4ID = "google/gemma-4-26B-A4B"
    static let glm51ID = "zai-org/GLM-5.1-FP8"
    static let glm52FP8ID = "zai-org/GLM-5.2-FP8"
    static let glm52NVFP4ID = "zai-org/GLM-5.2-NVFP4"
    static let gptOss120BID = "openai/gpt-oss-120b"
    static let kimiK3ID = "moonshotai/Kimi-K3"
    static let kimiK26ID = "nvidia/Kimi-K2.6-NVFP4"
    static let kimiK27ID = "moonshotai/Kimi-K2.7-Code"
    static let llama70BID = "meta-llama/Llama-3.3-70B-Instruct"
    static let llama70BFP8ID = "amd/Llama-3.3-70B-Instruct-FP8-KV"
    static let miniMaxM3ID = "MiniMaxAI/MiniMax-M3-MXFP8"
    static let qwen27BID = "unsloth/Qwen3.6-27B-NVFP4"
    static let qwen35BID = "unsloth/Qwen3.6-35B-A3B-NVFP4"

    enum ThinkingFormat: Equatable {
        /// Official DeepSeek `thinking: { type }` is ignored on Makora's vLLM.
        /// Flash needs both `include_reasoning` and `chat_template_kwargs.thinking`.
        case deepSeekFlash
        /// Pro needs `chat_template_kwargs.thinking` only.
        case deepSeekPro
        /// GLM / Qwen / Kimi / MiniMax / Gemma: `chat_template_kwargs.enable_thinking`.
        case enableThinking
        /// GPT-OSS: thinking always on; `include_reasoning` + `reasoning_effort`.
        case gptOss
        case none
    }

    static func canonicalModelID(for modelID: String) -> String {
        canonicalByLower[modelID.lowercased()] ?? modelID
    }

    static func thinkingFormat(for modelID: String) -> ThinkingFormat {
        switch modelID.lowercased() {
        case deepSeekV4FlashID.lowercased(), deepSeekV4Flash0731ID.lowercased():
            return .deepSeekFlash
        case deepSeekV4ProID.lowercased():
            return .deepSeekPro
        case gptOss120BID.lowercased():
            return .gptOss
        case gemma4ID.lowercased(),
             glm51ID.lowercased(),
             glm52FP8ID.lowercased(),
             glm52NVFP4ID.lowercased(),
             kimiK3ID.lowercased(),
             kimiK26ID.lowercased(),
             kimiK27ID.lowercased(),
             miniMaxM3ID.lowercased(),
             qwen27BID.lowercased(),
             qwen35BID.lowercased():
            return .enableThinking
        default:
            return .none
        }
    }

    static func isAlwaysOnReasoningModel(_ modelID: String) -> Bool {
        modelID.lowercased() == gptOss120BID.lowercased()
    }

    /// vLLM streaming parser is missing for these IDs (omp-makora-provider).
    static func disablesNativeToolChoice(_ modelID: String) -> Bool {
        switch modelID.lowercased() {
        case kimiK26ID.lowercased(),
             kimiK27ID.lowercased(),
             qwen27BID.lowercased(),
             qwen35BID.lowercased():
            return true
        default:
            return false
        }
    }

    /// GLM 5.1: force vLLM's explicit tool streaming path (`tool_stream: true`).
    static func usesToolStream(_ modelID: String) -> Bool {
        modelID.lowercased() == glm51ID.lowercased()
    }

    /// Assistant `tool_calls` crash ZAI/vLLM (`'str object' has no attribute 'items'`).
    /// Convert them back to `<tool_call>` XML on follow-up turns.
    static func stripsToolCallsOnFollowUp(_ modelID: String) -> Bool {
        switch modelID.lowercased() {
        case glm51ID.lowercased(),
             glm52FP8ID.lowercased(),
             glm52NVFP4ID.lowercased():
            return true
        default:
            return false
        }
    }

    static func needsClientSideToolCallRepair(_ modelID: String) -> Bool {
        switch modelID.lowercased() {
        case glm51ID.lowercased(),
             kimiK26ID.lowercased(),
             kimiK27ID.lowercased(),
             qwen27BID.lowercased(),
             qwen35BID.lowercased():
            return true
        default:
            return false
        }
    }

    /// Per-slug endpoint that is not on the unified `/v1` router.
    static func chatCompletionsURL(baseURL: String, modelID: String) -> String {
        let canonical = canonicalModelID(for: modelID)
        if canonical.lowercased() == llama70BFP8ID.lowercased() {
            return slugChatCompletionsURL(defaultSlugBaseURL: llamaFP8SlugBaseURL, configuredBaseURL: baseURL)
        }
        return "\(baseURL)/chat/completions"
    }

    static func modelsListURL(baseURL: String) -> String {
        "\(baseURL)/models"
    }

    private static func slugChatCompletionsURL(defaultSlugBaseURL: String, configuredBaseURL: String) -> String {
        guard let defaultURL = URL(string: defaultSlugBaseURL),
              let configured = URL(string: configuredBaseURL),
              let defaultHost = defaultURL.host,
              let configuredHost = configured.host else {
            return "\(defaultSlugBaseURL)/chat/completions"
        }

        if configuredHost.caseInsensitiveCompare(defaultHost) == .orderedSame
            || configuredHost.lowercased().hasSuffix(".\(defaultHost.lowercased())") {
            return "\(defaultSlugBaseURL)/chat/completions"
        }

        // Custom host (proxy / enterprise): keep the slug path, swap the origin.
        var components = URLComponents()
        components.scheme = configured.scheme ?? defaultURL.scheme
        components.host = configuredHost
        components.port = configured.port
        components.path = defaultURL.path.hasSuffix("/v1") ? "\(defaultURL.path)/chat/completions" : "\(defaultURL.path)/v1/chat/completions"
        return components.string ?? "\(defaultSlugBaseURL)/chat/completions"
    }

    private static let canonicalByLower: [String: String] = {
        let ids = [
            deepSeekV4FlashID,
            deepSeekV4Flash0731ID,
            deepSeekV4ProID,
            gemma4ID,
            glm51ID,
            glm52FP8ID,
            glm52NVFP4ID,
            gptOss120BID,
            kimiK3ID,
            kimiK26ID,
            kimiK27ID,
            llama70BID,
            llama70BFP8ID,
            miniMaxM3ID,
            qwen27BID,
            qwen35BID,
        ]
        return Dictionary(uniqueKeysWithValues: ids.map { ($0.lowercased(), $0) })
    }()
}
