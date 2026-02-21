import Foundation

actor SearchRedirectURLResolver {
    static let shared = SearchRedirectURLResolver()

    private struct CacheEntry: Sendable {
        let resolvedURL: String?
        let resolvedAt: Date
    }

    private struct DiskCacheEntry: Codable {
        let resolvedURL: String?
        let resolvedAt: Date

        enum CodingKeys: String, CodingKey {
            case resolvedURL
            case resolvedAt
        }

        init(resolvedURL: String?, resolvedAt: Date) {
            self.resolvedURL = resolvedURL
            self.resolvedAt = resolvedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            resolvedURL = try container.decodeIfPresent(String.self, forKey: .resolvedURL)

            if let timestamp = try? container.decode(Double.self, forKey: .resolvedAt) {
                resolvedAt = Date(timeIntervalSince1970: timestamp)
            } else if let timestamp = try? container.decode(Int.self, forKey: .resolvedAt) {
                resolvedAt = Date(timeIntervalSince1970: Double(timestamp))
            } else if let timestamp = try? container.decode(String.self, forKey: .resolvedAt),
                      let parsed = Double(timestamp) {
                resolvedAt = Date(timeIntervalSince1970: parsed)
            } else if let decodedDate = try? container.decode(Date.self, forKey: .resolvedAt) {
                resolvedAt = decodedDate
            } else {
                throw DecodingError.typeMismatch(
                    Date.self,
                    DecodingError.Context(
                        codingPath: [CodingKeys.resolvedAt],
                        debugDescription: "Unsupported timestamp format"
                    )
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(resolvedURL, forKey: .resolvedURL)
            try container.encode(resolvedAt.timeIntervalSince1970, forKey: .resolvedAt)
        }
    }

    private struct DiskCachePayload: Codable {
        let version: Int
        let entries: [String: DiskCacheEntry]

        init(version: Int = 1, entries: [String: DiskCacheEntry]) {
            self.version = version
            self.entries = entries
        }
    }

    private enum Configuration {
        static let cacheTTLSeconds: TimeInterval = 7 * 24 * 60 * 60
        static let cacheFileName = "SearchRedirectURLCache.json"
        static let cacheFileVersion = 1
        static let requestTimeout: TimeInterval = 8
    }

    private var cacheByRawURL: [String: CacheEntry] = [:]
    private var inFlightByRawURL: [String: Task<String?, Never>] = [:]
    private let cacheFileURL: URL?
    private let fileManager: FileManager
    private let session: URLSession
    private let now: () -> Date

    init(
        fileManager: FileManager = .default,
        cacheFileURL: URL? = nil,
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.cacheFileURL = cacheFileURL ?? Self.defaultCacheFileURL(fileManager: fileManager)
        self.session = session
        self.now = now
        cacheByRawURL = Self.loadCacheFromDisk(
            cacheFileURL: self.cacheFileURL,
            now: self.now
        )
    }

    func resolveIfNeeded(rawURL: String) async -> String? {
        guard let normalizedRawURL = SearchURLNormalizer.normalize(rawURL) else { return nil }
        guard shouldResolveRedirect(for: normalizedRawURL) else { return nil }

        if let cached = cacheByRawURL[normalizedRawURL] {
            if Self.isExpired(cached.resolvedAt, now: now()) {
                cacheByRawURL[normalizedRawURL] = nil
            } else {
                return cached.resolvedURL
            }
        }

        if let task = inFlightByRawURL[normalizedRawURL] {
            return await task.value
        }

        let task = Task<String?, Never> {
            await self.resolveFinalURLString(from: normalizedRawURL)
        }
        inFlightByRawURL[normalizedRawURL] = task

        let resolved = await task.value
        inFlightByRawURL[normalizedRawURL] = nil
        cacheByRawURL[normalizedRawURL] = CacheEntry(resolvedURL: resolved, resolvedAt: now())
        persistCacheToDisk()

        return resolved
    }

    static func defaultCacheFileURL(fileManager: FileManager) -> URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        return appSupport
            .appendingPathComponent("Jin", isDirectory: true)
            .appendingPathComponent(Configuration.cacheFileName)
    }

    private static func isExpired(_ date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) > Configuration.cacheTTLSeconds
    }

    private static func loadCacheFromDisk(cacheFileURL: URL?, now: @escaping () -> Date) -> [String: CacheEntry] {
        var loaded: [String: CacheEntry] = [:]
        guard let cacheFileURL else { return loaded }
        guard let data = try? Data(contentsOf: cacheFileURL) else { return loaded }

        let decoder = JSONDecoder()
        guard
            let decoded = try? decoder.decode(DiskCachePayload.self, from: data),
            decoded.version == Configuration.cacheFileVersion,
            !decoded.entries.isEmpty
        else {
            return loaded
        }

        let now = now()
        for (url, entry) in decoded.entries {
            guard !Self.isExpired(entry.resolvedAt, now: now) else { continue }
            loaded[url] = CacheEntry(resolvedURL: entry.resolvedURL, resolvedAt: entry.resolvedAt)
        }

        return loaded
    }

    private func persistCacheToDisk() {
        guard let cacheFileURL else { return }
        let validEntries = cacheByRawURL.compactMapValues { entry -> DiskCacheEntry? in
            guard !Self.isExpired(entry.resolvedAt, now: now()) else { return nil }
            return DiskCacheEntry(resolvedURL: entry.resolvedURL, resolvedAt: entry.resolvedAt)
        }

        guard !validEntries.isEmpty else {
            try? fileManager.removeItem(at: cacheFileURL)
            return
        }

        let parentDir = cacheFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let payload = DiskCachePayload(
            version: Configuration.cacheFileVersion,
            entries: validEntries
        )
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: cacheFileURL, options: .atomic)
    }

    private func resolveFinalURLString(from rawURL: String) async -> String? {
        guard let sourceURL = URL(string: rawURL) else { return nil }

        if let redirectedFromQuery = Self.resolveFromQueryParameters(sourceURL) {
            return redirectedFromQuery.absoluteString
        }

        var headRequest = URLRequest(url: sourceURL)
        headRequest.httpMethod = "HEAD"
        headRequest.timeoutInterval = Configuration.requestTimeout
        headRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if let finalURL = await followRedirects(using: headRequest),
           finalURL.absoluteString.caseInsensitiveCompare(rawURL) != .orderedSame {
            return finalURL.absoluteString
        }

        var probeRequest = URLRequest(url: sourceURL)
        probeRequest.httpMethod = "GET"
        probeRequest.timeoutInterval = Configuration.requestTimeout
        probeRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        probeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        if let finalURL = await followRedirects(using: probeRequest),
           finalURL.absoluteString.caseInsensitiveCompare(rawURL) != .orderedSame {
            return finalURL.absoluteString
        }

        return nil
    }

    private static func resolveFromQueryParameters(_ url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              !queryItems.isEmpty else {
            return nil
        }

        let redirectKeys = ["url", "u", "target", "dest", "redirect", "adurl", "link"]
        for key in redirectKeys {
            guard let raw = queryItems.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value,
                  let decoded = raw.removingPercentEncoding,
                  let redirected = URL(string: decoded) else {
                continue
            }
            return redirected
        }

        return nil
    }

    private func followRedirects(using request: URLRequest) async -> URL? {
        do {
            let (_, response) = try await session.data(for: request)
            return response.url
        } catch {
            return nil
        }
    }

    private func shouldResolveRedirect(for rawURL: String) -> Bool {
        guard let url = URL(string: rawURL),
              let host = url.host?.lowercased() else {
            return false
        }

        if host == "vertexaisearch.cloud.google.com" {
            return true
        }

        if (host == "google.com" || host == "www.google.com"),
           url.path.lowercased() == "/url" {
            return true
        }

        return false
    }
}
