import Foundation

enum OpenAIChatCompletionsImageSupport {
    static func imageOutputs(
        _ payloads: [OpenAIChatCompletionsResponse.GeneratedImage]?
    ) -> [ImageContent] {
        guard let payloads, !payloads.isEmpty else { return [] }
        return payloads.compactMap(imageContent(from:))
    }

    private static func imageContent(
        from payload: OpenAIChatCompletionsResponse.GeneratedImage
    ) -> ImageContent? {
        guard let rawURL = payload.resolvedImageURL?.trimmedNonEmpty else { return nil }

        if let parsed = parseDataURL(rawURL) {
            let mimeType = payload.mimeType ?? parsed.mimeType ?? "image/png"
            return ImageContent(mimeType: mimeType, data: parsed.data)
        }

        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }

        let mimeType = payload.mimeType ?? inferImageMIMEType(from: url) ?? "image/png"
        return ImageContent(mimeType: mimeType, data: nil, url: url, assetDisposition: .managed)
    }

    private static func parseDataURL(_ value: String) -> (mimeType: String?, data: Data)? {
        guard value.range(of: "data:", options: [.anchored, .caseInsensitive]) != nil,
              let commaIndex = value.firstIndex(of: ",") else {
            return nil
        }

        let metadataStart = value.index(value.startIndex, offsetBy: 5)
        let metadata = value[metadataStart..<commaIndex]
        let payloadStart = value.index(after: commaIndex)
        let payload = String(value[payloadStart...])

        let metadataParts = metadata
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { String($0).trimmed }
        let mimeType: String?
        if let firstPart = metadataParts.first,
           !firstPart.isEmpty,
           firstPart.contains("/") {
            mimeType = firstPart
        } else {
            mimeType = nil
        }

        if metadataParts.contains(where: { $0.caseInsensitiveCompare("base64") == .orderedSame }),
           let data = Data(base64Encoded: payload) {
            return (mimeType, data)
        }

        guard let decoded = payload.removingPercentEncoding?.data(using: .utf8) else {
            return nil
        }
        return (mimeType, decoded)
    }

    private static func inferImageMIMEType(from url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        default:
            return nil
        }
    }
}
