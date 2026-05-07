import Foundation

struct CloudflareR2UploadPayload {
    let data: Data
    let mimeType: String
    let fileExtension: String
}

struct CloudflareR2DataURL: Equatable {
    let mimeType: String?
    let data: Data

    init(_ value: String) throws {
        guard value.lowercased().hasPrefix("data:"),
              let commaIndex = value.firstIndex(of: ",") else {
            throw CloudflareR2UploaderError.malformedDataURL
        }

        let metadataRange = value.index(value.startIndex, offsetBy: 5)..<commaIndex
        let payloadRange = value.index(after: commaIndex)..<value.endIndex
        let metadata = String(value[metadataRange])
        let payload = String(value[payloadRange])

        let metadataParts = metadata.split(separator: ";").map(String.init)
        self.mimeType = metadataParts.first(where: { !$0.isEmpty })
        let isBase64 = metadataParts.contains(where: { $0.caseInsensitiveCompare("base64") == .orderedSame })

        if isBase64 {
            guard let data = Data(base64Encoded: payload) else {
                throw CloudflareR2UploaderError.malformedDataURL
            }
            self.data = data
        } else {
            guard let decoded = payload.removingPercentEncoding,
                  let data = decoded.data(using: .utf8) else {
                throw CloudflareR2UploaderError.malformedDataURL
            }
            self.data = data
        }
    }
}

enum CloudflareR2PayloadMetadata {
    static func videoMimeType(_ mimeType: String, fallbackURL: URL?) -> String {
        if let normalized = mimeType.trimmedNonEmpty?.lowercased() {
            return normalized
        }

        if let fallbackURL {
            switch fallbackURL.pathExtension.lowercased() {
            case "mov": return "video/quicktime"
            case "webm": return "video/webm"
            case "avi": return "video/x-msvideo"
            case "mkv": return "video/x-matroska"
            default: return "video/mp4"
            }
        }
        return "video/mp4"
    }

    static func videoFileExtension(for mimeType: String, fallbackURL: URL?) -> String {
        switch mimeType.lowercased() {
        case "video/quicktime":
            return "mov"
        case "video/webm":
            return "webm"
        case "video/x-msvideo":
            return "avi"
        case "video/x-matroska":
            return "mkv"
        case "video/mp4":
            return "mp4"
        default:
            if let fallback = fallbackURL?.pathExtension.trimmedNonEmpty {
                return fallback.lowercased()
            }
            return "mp4"
        }
    }

    static func fileMimeType(_ mimeType: String, fallbackURL: URL?) -> String {
        if let normalized = mimeType.trimmedNonEmpty?.lowercased() {
            return normalized
        }
        if fallbackURL?.pathExtension.lowercased() == "pdf" {
            return "application/pdf"
        }
        return "application/octet-stream"
    }

    static func fileExtension(for mimeType: String, fallbackURL: URL?) -> String {
        let normalized = fileMimeType(mimeType, fallbackURL: fallbackURL)
        switch normalized {
        case "application/pdf":
            return "pdf"
        default:
            if let fallback = fallbackURL?.pathExtension.trimmedNonEmpty {
                return fallback.lowercased()
            }
            return "bin"
        }
    }
}
