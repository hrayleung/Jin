import Foundation

actor SearchSourcePreviewResolver {
    static let shared = SearchSourcePreviewResolver()

    private var cacheByURL: [String: SearchSourcePreviewCacheEntry] = [:]
    private var inFlightByURL: [String: Task<String?, Never>] = [:]
    private let cacheFileURL: URL?
    private let overrideDataProvider: HTTPDataProvider?
    private let fileManager: FileManager
    private let now: () -> Date

    init(
        fileManager: FileManager = .default,
        cacheFileURL: URL? = nil,
        dataProvider: HTTPDataProvider? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.cacheFileURL = cacheFileURL ?? Self.defaultCacheFileURL(fileManager: fileManager)
        self.overrideDataProvider = dataProvider
        self.now = now
        cacheByURL = SearchSourcePreviewDiskCache.load(
            cacheFileURL: self.cacheFileURL,
            now: self.now
        )
    }

    static func defaultCacheFileURL(fileManager: FileManager) -> URL? {
        return try? AppDataLocations.searchPreviewCacheFileURL(fileManager: fileManager)
    }

    private func persistCacheToDisk() {
        SearchSourcePreviewDiskCache.persist(
            cacheByURL: cacheByURL,
            to: cacheFileURL,
            fileManager: fileManager,
            now: now
        )
    }

    func resolvePreviewIfNeeded(rawURL: String) async -> String? {
        guard let normalizedURL = SearchURLNormalizer.normalize(rawURL) else { return nil }
        let now = now()

        if let cached = cacheByURL[normalizedURL] {
            if SearchSourcePreviewDiskCache.isExpired(cached.fetchedAt, now: now) {
                cacheByURL[normalizedURL] = nil
            } else {
                return cached.previewText
            }
        }

        guard cacheByURL[normalizedURL] == nil else {
            return cacheByURL[normalizedURL]?.previewText
        }

        if let inFlightTask = inFlightByURL[normalizedURL] {
            return await inFlightTask.value
        }

        let task = Task<String?, Never> {
            await self.fetchPreviewText(from: normalizedURL)
        }
        inFlightByURL[normalizedURL] = task

        let preview = await task.value
        inFlightByURL[normalizedURL] = nil

        let resolvedAt = self.now()
        if let preview {
            cacheByURL[normalizedURL] = SearchSourcePreviewCacheEntry(previewText: preview, fetchedAt: resolvedAt)
            persistCacheToDisk()
        } else {
            cacheByURL[normalizedURL] = SearchSourcePreviewCacheEntry(previewText: nil, fetchedAt: resolvedAt)
        }

        return preview
    }

    private func fetchPreviewText(from normalizedURLString: String) async -> String? {
        guard !Task.isCancelled else { return nil }
        guard let url = URL(string: normalizedURLString), Self.shouldAttemptPreviewFetch(for: url) else {
            return nil
        }

        if let xStatusURL = Self.canonicalXStatusURLIfNeeded(for: url) {
            return await fetchXPostPreview(from: xStatusURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = SearchSourcePreviewConfiguration.requestTimeout
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(SearchSourcePreviewConfiguration.acceptHeader, forHTTPHeaderField: "Accept")
        request.setValue(SearchSourcePreviewConfiguration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-\(SearchSourcePreviewConfiguration.maxDownloadBytes - 1)", forHTTPHeaderField: "Range")

        do {
            let (data, response) = try await NetworkDebugRequestExecutor.data(
                for: request,
                mode: "search_preview",
                dataProvider: overrideDataProvider
            )
            guard !Task.isCancelled else { return nil }
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<400).contains(http.statusCode) else { return nil }
            guard Self.isLikelyHTML(response: http) else { return nil }

            let limitedData = Data(data.prefix(SearchSourcePreviewConfiguration.maxDownloadBytes))
            let html = String(data: limitedData, encoding: .utf8)
                ?? String(data: limitedData, encoding: .isoLatin1)
            guard let html else { return nil }

            return SearchSourcePreviewHTMLParser.extractPreview(from: html)
        } catch {
            return nil
        }
    }

    private func fetchXPostPreview(from statusURL: URL) async -> String? {
        guard var components = URLComponents(string: SearchSourcePreviewConfiguration.xOEmbedEndpoint) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: statusURL.absoluteString),
            URLQueryItem(name: "omit_script", value: "1"),
            URLQueryItem(name: "dnt", value: "true")
        ]
        guard let oEmbedURL = components.url else { return nil }

        var request = URLRequest(url: oEmbedURL)
        request.httpMethod = "GET"
        request.timeoutInterval = SearchSourcePreviewConfiguration.requestTimeout
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(SearchSourcePreviewConfiguration.jsonAcceptHeader, forHTTPHeaderField: "Accept")
        request.setValue(SearchSourcePreviewConfiguration.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await NetworkDebugRequestExecutor.data(
                for: request,
                mode: "search_preview_oembed",
                dataProvider: overrideDataProvider
            )
            guard !Task.isCancelled else { return nil }
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(http.statusCode) else { return nil }
            guard Self.isLikelyJSON(response: http, data: data) else { return nil }
            return Self.extractXPostPreview(fromOEmbedPayload: data)
        } catch {
            return nil
        }
    }

    private static func shouldAttemptPreviewFetch(for url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return false
        }

        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty, SearchSourcePreviewConfiguration.blockedPathExtensions.contains(pathExtension) {
            return false
        }

        return true
    }

    private static func isLikelyHTML(response: HTTPURLResponse) -> Bool {
        guard let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() else {
            return true
        }

        if contentType.contains("text/html") || contentType.contains("application/xhtml+xml") {
            return true
        }

        return !contentType.contains("json") && !contentType.contains("xml")
    }

    private static func isLikelyJSON(response: HTTPURLResponse, data: Data) -> Bool {
        if let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("json") {
            return true
        }

        let prefix = String(decoding: data.prefix(32), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.hasPrefix("{") || prefix.hasPrefix("[")
    }
}
