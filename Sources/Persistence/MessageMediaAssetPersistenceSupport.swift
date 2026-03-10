import AppKit
import CryptoKit
import Foundation

enum MessageMediaAssetPersistenceSupport {
    static func persistManagedRemoteImageToDisk(
        from url: URL,
        mimeType: String,
        dataProvider: HTTPDataProvider? = nil
    ) async -> URL? {
        do {
            let (data, response) = try await remoteData(from: url, mode: "attachment_image_download", dataProvider: dataProvider)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  !data.isEmpty else {
                return nil
            }
            if let mimeType = httpResponse.mimeType,
               !mimeType.lowercased().hasPrefix("image") {
                return nil
            }
            let filename = "generated-image.\(AttachmentStorageManager.fileExtension(for: mimeType) ?? fallbackExtension(from: url, defaultValue: "png"))"
            let storage = try AttachmentStorageManager()
            let stored = try await storage.saveAttachment(data: data, filename: filename, mimeType: mimeType)
            return stored.fileURL
        } catch {
            return nil
        }
    }

    static func persistRemoteVideoToDisk(from url: URL, dataProvider: HTTPDataProvider? = nil) async -> URL? {
        do {
            let (data, response) = try await remoteData(from: url, mode: "attachment_video_download", dataProvider: dataProvider)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  !data.isEmpty else {
                return nil
            }
            let contentType = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Type")?
                .components(separatedBy: ";").first?
                .trimmingCharacters(in: .whitespaces)
                .lowercased()

            let ext = videoFileExtension(contentType: contentType, url: url)
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            guard let dir = appSupport?.appendingPathComponent("Jin/Attachments", isDirectory: true) else { return nil }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let destination = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    static func persistImageToDisk(data: Data?, image: NSImage, mimeType: String) -> URL? {
        let imageData: Data
        if let data {
            imageData = data
        } else if let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) {
            imageData = png
        } else {
            return nil
        }

        let ext = AttachmentStorageManager.fileExtension(for: mimeType) ?? "png"
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let dir = appSupport?.appendingPathComponent("Jin/Attachments", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let hash = SHA256.hash(data: imageData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        let url = dir.appendingPathComponent("\(hashString).\(ext)")

        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        do {
            try imageData.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    private static func remoteData(from url: URL, mode: String, dataProvider: HTTPDataProvider?) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await NetworkDebugRequestExecutor.data(for: request, mode: mode, dataProvider: dataProvider)
    }

    private static func fallbackExtension(from url: URL, defaultValue: String) -> String {
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ext.isEmpty ? defaultValue : ext
    }

    private static func videoFileExtension(contentType: String?, url: URL) -> String {
        let mimeToExt: [String: String] = [
            "video/mp4": "mp4",
            "video/quicktime": "mov",
            "video/webm": "webm",
            "video/x-msvideo": "avi",
            "video/x-matroska": "mkv",
        ]

        if let contentType, let ext = mimeToExt[contentType] {
            return ext
        }

        return fallbackExtension(from: url, defaultValue: "mp4")
    }
}
