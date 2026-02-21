import Foundation

/// Shared utilities for downloading and saving video files to the local attachments directory.
enum VideoAttachmentUtility {

    /// Downloads a video from the given URL and saves it to the local attachments directory.
    static func downloadToLocal(
        from url: URL,
        networkManager: NetworkManager,
        authHeader: (key: String, value: String)? = nil
    ) async throws -> (localURL: URL, mimeType: String) {
        let dir = try attachmentsDirectory()

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let auth = authHeader {
            request.addValue(auth.value, forHTTPHeaderField: auth.key)
        }

        let (videoData, response) = try await networkManager.sendRequest(request)

        let contentType = response.value(forHTTPHeaderField: "Content-Type")?
            .components(separatedBy: ";").first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        let (mimeType, ext) = resolveVideoFormat(contentType: contentType, url: url)

        let filename = "\(UUID().uuidString).\(ext)"
        let destination = dir.appendingPathComponent(filename)
        try videoData.write(to: destination, options: .atomic)
        return (destination, mimeType)
    }

    /// Saves raw video data to the local attachments directory.
    static func saveDataToLocal(_ data: Data, mimeType: String) throws -> URL {
        let dir = try attachmentsDirectory()

        let ext = extensionForMIME(mimeType) ?? "mp4"
        let filename = "\(UUID().uuidString).\(ext)"
        let destination = dir.appendingPathComponent(filename)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    /// Resolves a video MIME type and file extension from an HTTP Content-Type header and/or URL.
    static func resolveVideoFormat(contentType: String?, url: URL) -> (mimeType: String, ext: String) {
        if let ct = contentType, let ext = mimeToExtension[ct] {
            return (ct, ext)
        }

        let urlExt = url.pathExtension.lowercased()
        if !urlExt.isEmpty {
            if let mime = extensionToMIME[urlExt] {
                return (mime, urlExt)
            }
            return ("video/\(urlExt)", urlExt)
        }

        return ("video/mp4", "mp4")
    }

    // MARK: - Private

    private static let mimeToExtension: [String: String] = [
        "video/mp4": "mp4",
        "video/quicktime": "mov",
        "video/webm": "webm",
        "video/x-msvideo": "avi",
        "video/x-matroska": "mkv",
    ]

    private static let extensionToMIME: [String: String] = [
        "mp4": "video/mp4",
        "mov": "video/quicktime",
        "webm": "video/webm",
        "avi": "video/x-msvideo",
        "mkv": "video/x-matroska",
    ]

    private static func extensionForMIME(_ mimeType: String) -> String? {
        mimeToExtension[mimeType.lowercased()]
    }

    private static func attachmentsDirectory() throws -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw LLMError.decodingError(
                message: "Could not locate application support directory for video storage."
            )
        }

        let dir = appSupport.appendingPathComponent("Jin/Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
