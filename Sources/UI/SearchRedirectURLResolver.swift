import Foundation

actor SearchRedirectURLResolver {
    static let shared = SearchRedirectURLResolver()

    private enum CacheLookup {
        case hit(String?)
        case miss
    }

    private struct RedirectProbe {
        let method: String
        let debugMode: String
        let headers: [String: String]

        static let orderedProbes = [
            RedirectProbe(method: "HEAD", debugMode: "search_redirect_head", headers: [:]),
            RedirectProbe(method: "GET", debugMode: "search_redirect_get", headers: ["Range": "bytes=0-0"])
        ]

        func request(for sourceURL: URL) -> URLRequest {
            var request = URLRequest(url: sourceURL)
            request.httpMethod = method
            request.timeoutInterval = Configuration.requestTimeout
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            for (header, value) in headers {
                request.setValue(value, forHTTPHeaderField: header)
            }

            return request
        }
    }

    private enum Configuration {
        static let requestTimeout: TimeInterval = 8
        static let redirectTargetQueryKeys = SearchRedirectQueryParameterSupport.targetURLKeysIncludingLink
    }

    private var cacheByRawURL: [String: SearchRedirectURLCacheStore.Entry] = [:]
    private var inFlightByRawURL: [String: Task<String?, Never>] = [:]
    private let cacheFileURL: URL?
    private let fileManager: FileManager
    private let overrideDataProvider: HTTPDataProvider?
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
        cacheByRawURL = SearchRedirectURLCacheStore.load(
            from: self.cacheFileURL,
            now: self.now()
        )
    }

    func resolveIfNeeded(rawURL: String) async -> String? {
        guard let normalizedRawURL = SearchURLNormalizer.normalize(rawURL) else { return nil }
        guard shouldResolveRedirect(for: normalizedRawURL) else { return nil }

        switch cachedResolution(for: normalizedRawURL) {
        case .hit(let resolvedURL):
            return resolvedURL
        case .miss:
            break
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
        storeResolution(resolved, for: normalizedRawURL)

        return resolved
    }

    static func defaultCacheFileURL(fileManager: FileManager) -> URL? {
        return try? AppDataLocations.searchRedirectCacheFileURL(fileManager: fileManager)
    }

    private func cachedResolution(for rawURL: String) -> CacheLookup {
        guard let cached = cacheByRawURL[rawURL] else { return .miss }

        guard !SearchRedirectURLCacheStore.isExpired(cached.resolvedAt, now: now()) else {
            cacheByRawURL[rawURL] = nil
            return .miss
        }

        return .hit(cached.resolvedURL)
    }

    private func storeResolution(_ resolvedURL: String?, for rawURL: String) {
        let now = now()
        cacheByRawURL[rawURL] = SearchRedirectURLCacheStore.Entry(
            resolvedURL: resolvedURL,
            resolvedAt: now
        )
        SearchRedirectURLCacheStore.persist(
            cacheByRawURL,
            to: cacheFileURL,
            fileManager: fileManager,
            now: now
        )
    }

    private func resolveFinalURLString(from rawURL: String) async -> String? {
        guard let sourceURL = URL(string: rawURL) else { return nil }

        if let redirectedFromQuery = Self.resolveFromQueryParameters(sourceURL) {
            return redirectedFromQuery.absoluteString
        }

        for probe in RedirectProbe.orderedProbes {
            if let finalURL = await followRedirects(using: probe.request(for: sourceURL), mode: probe.debugMode),
               Self.isRedirected(finalURL, from: rawURL) {
                return finalURL.absoluteString
            }
        }

        return nil
    }

    private static func isRedirected(_ finalURL: URL, from rawURL: String) -> Bool {
        finalURL.absoluteString.caseInsensitiveCompare(rawURL) != .orderedSame
    }

    private static func resolveFromQueryParameters(_ url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              !queryItems.isEmpty else {
            return nil
        }

        return SearchRedirectQueryParameterSupport.firstDecodedURL(
            from: queryItems,
            matchingAnyOf: Configuration.redirectTargetQueryKeys
        )
    }

    private func followRedirects(using request: URLRequest, mode: String) async -> URL? {
        do {
            let (_, response) = try await NetworkDebugRequestExecutor.data(
                for: request,
                mode: mode,
                dataProvider: overrideDataProvider
            )
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
