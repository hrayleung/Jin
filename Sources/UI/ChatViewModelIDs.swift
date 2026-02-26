import Foundation

// MARK: - Static Model ID Sets

/// Model-family identification constants used by ChatView to detect
/// feature-specific capabilities that aren't yet surfaced through ModelInfo.
extension ChatView {

    static let xAIImageGenerationModelIDs: Set<String> = [
        "grok-imagine-image",
        "grok-imagine-image-pro",
        "grok-2-image-1212",
    ]

    static let xAIVideoGenerationModelIDs: Set<String> = [
        "grok-imagine-video",
    ]

    static let geminiImageGenerationModelIDs: Set<String> = [
        "gemini-3-pro-image-preview",
        "gemini-2.5-flash-image",
    ]

    static let googleVideoGenerationModelIDs: Set<String> = [
        "veo-2",
        "veo-3",
    ]

    static let openAIAudioInputModelIDs: Set<String> = [
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

    static let mistralAudioInputModelIDs: Set<String> = [
        "voxtral-large-latest",
        "voxtral-small-latest",
    ]

    static let mistralTranscriptionOnlyModelIDs: Set<String> = [
        "voxtral-mini-2602",
        "voxtral-mini-latest",
    ]

    static let geminiAudioInputModelIDs: Set<String> = [
        "gemini-3",
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro-preview",
        "gemini-3-flash-preview",
        "gemini-2.5",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.0-flash",
        "gemini-2.0-flash-lite",
    ]

    static let qwenAudioInputModelIDs: Set<String> = [
        "qwen3-asr-4b",
        "qwen3-asr-0.6b",
        "qwen3-omni-30b-a3b-instruct",
        "qwen3-omni-30b-a3b-thinking",
    ]

    static let fireworksAudioInputModelIDs: Set<String> = [
        "qwen3-asr-4b",
        "qwen3-asr-0.6b",
        "qwen3-omni-30b-a3b-instruct",
        "qwen3-omni-30b-a3b-thinking",
        "fireworks/qwen3-asr-4b",
        "fireworks/qwen3-asr-0.6b",
        "fireworks/qwen3-omni-30b-a3b-instruct",
        "fireworks/qwen3-omni-30b-a3b-thinking",
        "accounts/fireworks/models/qwen3-asr-4b",
        "accounts/fireworks/models/qwen3-asr-0.6b",
        "accounts/fireworks/models/qwen3-omni-30b-a3b-instruct",
        "accounts/fireworks/models/qwen3-omni-30b-a3b-thinking",
    ]

    static let compatibleAudioInputModelIDs: Set<String> = {
        openAIAudioInputModelIDs
            .union(mistralAudioInputModelIDs)
            .union(qwenAudioInputModelIDs)
            .union(geminiAudioInputModelIDs)
    }()

    static let gemini3ProModelIDs: Set<String> = [
        "gemini-3-pro",
        "gemini-3-pro-preview",
        "gemini-3.1-pro-preview",
        "gemini-3-pro-image-preview",
    ]

    static let vertexGemini25TextModelIDs: Set<String> = [
        "gemini-2.5",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
    ]

    static let geminiPreferredModelOrder: [String] = [
        "gemini-3.1-pro-preview",
        "gemini-3-pro-preview",
        "gemini-3-pro",
        "gemini-3-flash-preview",
    ]
}
