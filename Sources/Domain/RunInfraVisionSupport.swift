import Foundation

/// RunInfra Chat Completions vision contract.
///
/// Official (chat-completions reference, re-read 2026-09-29): Qwen3.8 27B, Ornith 1.5 35B,
/// GLM 5.3 Flash and Qwen3.8 Flash Next accept inline `image_url` / `input_image` parts as data
/// URLs, up to 8 images per request (runinfra.ai/docs/api-reference/chat-completions).
enum RunInfraVisionSupport {
    static let maxImagesPerRequest = 8
}
