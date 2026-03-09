import Foundation
import Kingfisher

enum FaviconSourceResolver {
    enum Configuration {
        static let requestTimeout: TimeInterval = 6
        static let acceptHeader = "image/*,*/*;q=0.8"
        static let userAgent = "Mozilla/5.0 Jin/1.0"
        static let secondLevelDomainPrefixes: Set<String> = [
            "ac", "co", "com", "edu", "gov", "net", "org"
        ]
    }

    struct ResolvedSources {
        let normalizedHost: String
        let cacheKey: String
        let primary: Source
        let alternatives: [Source]
    }

    static let requestModifier = AnyModifier { request in
        var modifiedRequest = request
        modifiedRequest.timeoutInterval = Configuration.requestTimeout
        modifiedRequest.setValue(Configuration.acceptHeader, forHTTPHeaderField: "Accept")
        modifiedRequest.setValue(Configuration.userAgent, forHTTPHeaderField: "User-Agent")
        return modifiedRequest
    }

    static let imageDownloader: ImageDownloader = {
        let downloader = ImageDownloader(name: "favicon")
        downloader.downloadTimeout = Configuration.requestTimeout
        return downloader
    }()

    static func sources(for rawHost: String) -> ResolvedSources? {
        guard let host = normalizedHost(from: rawHost) else { return nil }

        let cacheKey = "favicon_\(host)"
        let allSources = hostCandidates(for: host)
            .flatMap { requestURLs(for: $0) }
            .map { url in
                Source.network(KF.ImageResource(downloadURL: url, cacheKey: cacheKey))
            }

        guard let primary = allSources.first else { return nil }

        return ResolvedSources(
            normalizedHost: host,
            cacheKey: cacheKey,
            primary: primary,
            alternatives: Array(allSources.dropFirst())
        )
    }

    static func options(
        for resolved: ResolvedSources,
        cache: ImageCache = .default,
        downloader: ImageDownloader = imageDownloader
    ) -> KingfisherOptionsInfo {
        [
            .targetCache(cache),
            .originalCache(cache),
            .downloader(downloader),
            .requestModifier(requestModifier),
            .alternativeSources(resolved.alternatives)
        ]
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
}
