import Foundation

extension GeminiModelConstants {
    /// Builds a Google `inlineData` part from raw data or a file URL.
    /// Shared by both GeminiAdapter and VertexAIAdapter content translation.
    static func inlineDataPart(mimeType: String, data: Data?, url: URL?) throws -> [String: Any]? {
        if let data {
            return [
                "inlineData": [
                    "mimeType": mimeType,
                    "data": data.base64EncodedString()
                ]
            ]
        }

        if let url, url.isFileURL {
            let data = try resolveFileData(from: url)
            return [
                "inlineData": [
                    "mimeType": mimeType,
                    "data": data.base64EncodedString()
                ]
            ]
        }

        return nil
    }
}
