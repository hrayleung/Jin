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
            if let dataProvider {
                // Injected provider path (tests): buffered by construction.
                let (data, response) = try await remoteData(from: url, mode: "attachment_video_download", dataProvider: dataProvider)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      !data.isEmpty,
                      data.count <= RemoteMediaURLPolicy.maximumAutomaticVideoFetchBytes else {
                    return nil
                }
                return try writeVideo(data: data, contentType: videoContentType(from: httpResponse), url: url)
            }

            // Stream to disk: videos run tens to hundreds of MB, and the
            // previous buffered path (plus its lack of any size cap) held the
            // whole payload in RAM. `URLSession.shared` — one process-wide
            // session, nothing to invalidate.
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (tempURL, response) = try await URLSession.shared.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                try? FileManager.default.removeItem(at: tempURL)
                return nil
            }
            let fileSize = (try? tempURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard fileSize > 0, fileSize <= RemoteMediaURLPolicy.maximumAutomaticVideoFetchBytes else {
                try? FileManager.default.removeItem(at: tempURL)
                return nil
            }

            let ext = videoFileExtension(contentType: videoContentType(from: httpResponse), url: url)
            try AppDataLocations.ensureDirectoriesExist()
            guard let dir = try? AppDataLocations.attachmentsDirectoryURL() else {
                try? FileManager.default.removeItem(at: tempURL)
                return nil
            }
            let destination = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try VideoAttachmentUtility.moveReplacingDestination(from: tempURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private static func writeVideo(data: Data, contentType: String?, url: URL) throws -> URL? {
        let ext = videoFileExtension(contentType: contentType, url: url)
        try AppDataLocations.ensureDirectoriesExist()
        guard let dir = try? AppDataLocations.attachmentsDirectoryURL() else { return nil }
        let destination = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try data.write(to: destination, options: .atomic)
        return destination
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

    /// Shared session for bounded remote-image fetches. Static so it exists
    /// once for the process: a `URLSession` retains itself (plus its queue)
    /// until `invalidateAndCancel`, so the previous per-call session leaked
    /// one session per imported image.
    private static let boundedImageFetchSession = URLSession(
        configuration: NetworkDebugRequestExecutor.makeDefaultSessionConfiguration()
    )

    private static func boundedRemoteImageData(from url: URL, mode: String, dataProvider: HTTPDataProvider?) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        if let dataProvider {
            let (data, response) = try await NetworkDebugRequestExecutor.data(for: request, mode: mode, dataProvider: dataProvider)
            try validateRemoteImageResponse(response, byteCount: data.count)
            return (data, response)
        }

        // Streamed, not buffered-then-checked: a chunked response (or one
        // that under-declares Content-Length) must hit the size cap while the
        // bytes arrive, or an oversized URL buffers unbounded memory before
        // validation ever sees a byte count.
        let (bytes, response) = try await boundedImageFetchSession.bytes(for: request)
        try validateRemoteImageResponse(response, byteCount: nil)

        var data = Data()
        data.reserveCapacity(min(RemoteMediaURLPolicy.maximumAutomaticFetchBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            if data.count >= RemoteMediaURLPolicy.maximumAutomaticFetchBytes {
                throw URLError(.dataLengthExceedsMaximum)
            }
            data.append(byte)
        }
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

    private static func videoContentType(from response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: "Content-Type")?
            .components(separatedBy: ";").first?
            .trimmedLowercased
    }

    private static func videoFileExtension(contentType: String?, url: URL) -> String {
        VideoAttachmentUtility.resolveVideoFormat(contentType: contentType, url: url).ext
    }
}
