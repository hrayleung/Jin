import AppKit
import Foundation

enum MessageMediaAssetPersistenceSupport {
    static func persistManagedRemoteImageToDisk(
        from url: URL,
        mimeType: String,
        dataProvider: HTTPDataProvider? = nil
    ) async -> URL? {
        do {
            guard RemoteMediaURLPolicy.isAllowedForAutomaticFetch(url) else {
                return nil
            }

            let (data, response) = try await boundedRemoteImageData(
                from: url,
                mode: "attachment_image_download",
                dataProvider: dataProvider
            )
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  !data.isEmpty,
                  data.count <= RemoteMediaURLPolicy.maximumAutomaticFetchBytes else {
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
                .trimmedLowercased

            let ext = videoFileExtension(contentType: contentType, url: url)
            try AppDataLocations.ensureDirectoriesExist()
            guard let dir = try? AppDataLocations.attachmentsDirectoryURL() else { return nil }

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
        try? AppDataLocations.ensureDirectoriesExist()
        guard let dir = try? AppDataLocations.attachmentsDirectoryURL() else { return nil }

        let hashString = SHA256HexDigest.data(imageData)
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

    private static func boundedRemoteImageData(from url: URL, mode: String, dataProvider: HTTPDataProvider?) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        // One shared session for every caller: the previous path built a new
        // `URLSession` per fetch and never invalidated it — a URLSession
        // retains itself (plus its queue) until `invalidateAndCancel`, so each
        // remote-image import leaked one. The size cap is still enforced via
        // the declared Content-Length and the actual byte count.
        let (data, response) = try await NetworkDebugRequestExecutor.data(
            for: request,
            mode: mode,
            dataProvider: dataProvider
        )
        try validateRemoteImageResponse(response, byteCount: data.count)
        return (data, response)
    }

    private static func validateRemoteImageResponse(_ response: URLResponse, byteCount: Int?) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.expectedContentLength > Int64(RemoteMediaURLPolicy.maximumAutomaticFetchBytes) {
            throw URLError(.dataLengthExceedsMaximum)
        }
        if let byteCount, byteCount > RemoteMediaURLPolicy.maximumAutomaticFetchBytes {
            throw URLError(.dataLengthExceedsMaximum)
        }
        if let mimeType = httpResponse.mimeType,
           !mimeType.lowercased().hasPrefix("image") {
            throw URLError(.cannotDecodeContentData)
        }
    }

    private static func remoteData(from url: URL, mode: String, dataProvider: HTTPDataProvider?) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await NetworkDebugRequestExecutor.data(for: request, mode: mode, dataProvider: dataProvider)
    }

    private static func fallbackExtension(from url: URL, defaultValue: String) -> String {
        url.pathExtension.trimmedLowercased.trimmedNonEmpty ?? defaultValue
    }

    private static func videoFileExtension(contentType: String?, url: URL) -> String {
        VideoAttachmentUtility.resolveVideoFormat(contentType: contentType, url: url).ext
    }
}
