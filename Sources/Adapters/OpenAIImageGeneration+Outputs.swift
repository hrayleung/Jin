import Foundation

extension OpenAIAdapter {
    func resolveImageOutputs(
        from items: [OpenAIImageItem],
        controls: GenerationControls
    ) -> [ImageContent] {
        let outputFormat = controls.openaiImageGeneration?.outputFormat
        let defaultMIME = outputFormat?.mimeType ?? "image/png"

        return items.compactMap { item in
            if let b64 = item.b64Json, let data = Data(base64Encoded: b64) {
                return ImageContent(mimeType: defaultMIME, data: data, url: nil)
            }
            if let urlString = item.url, let url = URL(string: urlString) {
                let mime = inferImageMIMEType(from: url) ?? defaultMIME
                return ImageContent(mimeType: mime, data: nil, url: url, assetDisposition: .managed)
            }
            return nil
        }
    }

    private func inferImageMIMEType(from url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        default: return nil
        }
    }
}

struct OpenAIImageGenerationResponse: Codable {
    let created: Int?
    let data: [OpenAIImageItem]?
    let error: OpenAIImageAPIError?
}

struct OpenAIImageItem: Codable {
    let url: String?
    let b64Json: String?
    let revisedPrompt: String?
}

struct OpenAIImageAPIError: Codable {
    let code: String?
    let message: String
}
