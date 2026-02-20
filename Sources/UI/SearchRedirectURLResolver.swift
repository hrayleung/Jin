import Foundation

actor SearchRedirectURLResolver {
    static let shared = SearchRedirectURLResolver()

    private enum ResolutionCacheEntry: Sendable {
        case resolved(String)
        case unresolved
    }

    private var cacheByRawURL: [String: ResolutionCacheEntry] = [:]
    private var inFlightByRawURL: [String: Task<String?, Never>] = [:]

    func resolveIfNeeded(rawURL: String) async -> String? {
        guard let normalizedRawURL = SearchURLNormalizer.normalize(rawURL) else { return nil }
        guard shouldResolveRedirect(for: normalizedRawURL) else { return nil }

        if let cached = cacheByRawURL[normalizedRawURL] {
            switch cached {
            case .resolved(let value):
                return value
            case .unresolved:
                return nil
            }
        }

        if let task = inFlightByRawURL[normalizedRawURL] {
            return await task.value
        }

        let task = Task<String?, Never> {
            await Self.resolveFinalURLString(from: normalizedRawURL)
        }
        inFlightByRawURL[normalizedRawURL] = task

        let resolved = await task.value
        inFlightByRawURL[normalizedRawURL] = nil

        if let resolved {
            cacheByRawURL[normalizedRawURL] = .resolved(resolved)
        } else {
            cacheByRawURL[normalizedRawURL] = .unresolved
        }

        return resolved
    }

    private static func resolveFinalURLString(from rawURL: String) async -> String? {
        guard let sourceURL = URL(string: rawURL) else { return nil }

        var headRequest = URLRequest(url: sourceURL)
        headRequest.httpMethod = "HEAD"
        headRequest.timeoutInterval = 8
        headRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if let finalURL = await followRedirects(using: headRequest),
           finalURL.absoluteString.caseInsensitiveCompare(rawURL) != .orderedSame {
            return finalURL.absoluteString
        }

        var probeRequest = URLRequest(url: sourceURL)
        probeRequest.httpMethod = "GET"
        probeRequest.timeoutInterval = 8
        probeRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        probeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        if let finalURL = await followRedirects(using: probeRequest),
           finalURL.absoluteString.caseInsensitiveCompare(rawURL) != .orderedSame {
            return finalURL.absoluteString
        }

        return nil
    }

    private static func followRedirects(using request: URLRequest) async -> URL? {
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
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
