import Foundation

/// RunInfra Chat Completions vision contract.
///
/// Official: `qwen3-8-27b` accepts inline `image_url` / `input_image` parts,
/// up to 8 images per request (runinfra.ai/docs/api-reference/chat-completions).
enum RunInfraVisionSupport {
    static let maxImagesPerRequest = 8
}
