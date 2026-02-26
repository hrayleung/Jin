import Foundation

actor WebsiteFaviconRepository {
    static let shared = WebsiteFaviconRepository()

    private struct CacheEntry: Sendable {
        let data: Data?
        let fetchedAt: Date
    }

    private enum Configuration {
        static let requestTimeout: TimeInterval = 6
        static let successCacheTTL: TimeInterval = 30 * 24 * 60 * 60
        static let failureCacheTTL: TimeInterval = 15 * 60
        static let acceptHeader = "image/*,*/*;q=0.8"
        static let userAgent = "Mozilla/5.0 Jin/1.0"
        static let secondLevelDomainPrefixes: Set<String> = [
            "ac", "co", "com", "edu", "gov", "net", "org"
        ]
    }

    private var cacheByHost: [String: CacheEntry] = [:]
    private var inFlightByHost: [String: Task<Data?, Never>] = [:]

    func faviconData(for rawHost: String) async -> Data? {
        guard let normalizedHost = Self.normalizedHost(from: rawHost) else { return nil }

        let now = Date()
        if let cached = cacheByHost[normalizedHost],
           !Self.isExpired(cached, now: now) {
            return cached.data
        }
        cacheByHost[normalizedHost] = nil

        if let inFlightTask = inFlightByHost[normalizedHost] {
            return await inFlightTask.value
        }

        let task = Task<Data?, Never> {
            await Self.fetchFaviconData(for: normalizedHost)
        }
        inFlightByHost[normalizedHost] = task

        let data = await task.value
        inFlightByHost[normalizedHost] = nil
        cacheByHost[normalizedHost] = CacheEntry(data: data, fetchedAt: Date())
        return data
    }

    static func normalizedHost(from rawHost: String) -> String? {
        let trimmed = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let parsedURL = URL(string: trimmed), let host = parsedURL.host?.lowercased() {
            return host
        }

        if let parsedURL = URL(string: "https://\(trimmed)"), let host = parsedURL.host?.lowercased() {
            return host
        }

        return nil
    }

    static func hostCandidates(for normalizedHost: String) -> [String] {
        let host = normalizedHost.lowercased()
        var candidates: [String] = [host]
        let labels = host.split(separator: ".")
        guard labels.count > 2 else { return candidates }

        let suffixCount: Int
        if let topLevel = labels.last,
           let secondLevel = labels.dropLast().last,
           topLevel.count == 2,
           Configuration.secondLevelDomainPrefixes.contains(String(secondLevel)) {
            suffixCount = 3
        } else {
            suffixCount = 2
        }

        guard labels.count >= suffixCount else { return candidates }
        let apex = labels.suffix(suffixCount).joined(separator: ".")
        if apex != host {
            candidates.append(apex)
        }

        return candidates
    }

    static func requestURLs(for host: String) -> [URL] {
        var urls: [URL] = []

        if let duckDuckGoURL = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") {
            urls.append(duckDuckGoURL)
        }

        var googleByDomain = URLComponents(string: "https://www.google.com/s2/favicons")
        googleByDomain?.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "64")
        ]
        if let url = googleByDomain?.url {
            urls.append(url)
        }

        var googleByDomainURL = URLComponents(string: "https://www.google.com/s2/favicons")
        googleByDomainURL?.queryItems = [
            URLQueryItem(name: "domain_url", value: "https://\(host)"),
            URLQueryItem(name: "sz", value: "64")
        ]
        if let url = googleByDomainURL?.url {
            urls.append(url)
        }

        return urls
    }

    private static func isExpired(_ entry: CacheEntry, now: Date) -> Bool {
        let ttl = entry.data == nil ? Configuration.failureCacheTTL : Configuration.successCacheTTL
        return now.timeIntervalSince(entry.fetchedAt) > ttl
    }

    private static func fetchFaviconData(for normalizedHost: String) async -> Data? {
        for hostCandidate in hostCandidates(for: normalizedHost) {
            for requestURL in requestURLs(for: hostCandidate) {
                guard let data = await fetchImageData(from: requestURL) else { continue }
                return data
            }
        }
        return nil
    }

    private static func fetchImageData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Configuration.requestTimeout
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(Configuration.acceptHeader, forHTTPHeaderField: "Accept")
        request.setValue(Configuration.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            guard (200...299).contains(httpResponse.statusCode), !data.isEmpty else { return nil }

            if let mimeType = httpResponse.mimeType,
               !mimeType.lowercased().hasPrefix("image") {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
