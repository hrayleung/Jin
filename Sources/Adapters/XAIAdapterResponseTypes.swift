import Foundation

// MARK: - Models Response

struct XAIModelsResponse: Codable {
    let data: [XAIModelData]
}

struct XAIModelData: Codable {
    let id: String
    let inputModalities: [String]?
    let outputModalities: [String]?
    let modalities: [String]?
    let contextWindow: Int?
}

// MARK: - Media Generation Response Types

struct XAIAPIError: Codable {
    let code: String?
    let message: String
}

struct XAIMediaItem: Codable {
    let url: String?
    let imageUrl: String?
    let videoUrl: String?
    let resultUrl: String?
    let b64Json: String?
    let mimeType: String?

    var b64JSON: String? {
        b64Json
    }

    var resolvedURL: String? {
        url ?? imageUrl ?? videoUrl ?? resultUrl
    }
}

struct XAIImageGenerationResponse: Codable {
    let id: String?
    let requestId: String?
    let responseId: String?
    let data: [XAIMediaItem]?
    let output: [XAIMediaItem]?
    let result: [XAIMediaItem]?
    let images: [XAIMediaItem]?
    let url: String?
    let imageUrl: String?
    let b64Json: String?
    let mimeType: String?
    let error: XAIAPIError?

    var resolvedID: String? {
        requestId ?? responseId ?? id
    }

    var mediaItems: [XAIMediaItem] {
        var merged: [XAIMediaItem] = []
        for collection in [data, output, result, images] {
            if let collection {
                merged.append(contentsOf: collection)
            }
        }

        if let inline = inlineMediaItem {
            merged.append(inline)
        }

        return merged
    }

    private var inlineMediaItem: XAIMediaItem? {
        guard url != nil || imageUrl != nil || b64Json != nil else {
            return nil
        }

        return XAIMediaItem(
            url: url,
            imageUrl: imageUrl,
            videoUrl: nil,
            resultUrl: nil,
            b64Json: b64Json,
            mimeType: mimeType
        )
    }
}

// MARK: - Video Generation Response Types

/// Flexible start response - the xAI API may return the identifier under
/// `request_id`, `response_id`, or `id` depending on the endpoint version.
struct XAIVideoStartResponse: Codable {
    let requestId: String?
    let responseId: String?
    let id: String?
    let error: XAIAPIError?

    var resolvedID: String? {
        requestId ?? responseId ?? id
    }
}

struct XAIVideoStatusResponse: Codable {
    let status: String?
    let video: XAIVideoResult?
    let model: String?
    let result: XAIVideoResult?
    let error: XAIAPIError?

    /// The video result may live under `video` or `result`.
    var resolvedVideo: XAIVideoResult? {
        video ?? result
    }

    /// Normalised status string; defaults to "pending" if absent.
    var resolvedStatus: String {
        (status ?? "pending").lowercased()
    }
}

struct XAIVideoResult: Codable {
    let url: String?
    let duration: Int?
}
