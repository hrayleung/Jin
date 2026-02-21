import Foundation

actor SearchSourcePreviewResolver {
    static let shared = SearchSourcePreviewResolver()

    private struct CacheEntry: Sendable {
        let previewText: String?
        let fetchedAt: Date
    }

    private struct DiskCacheEntry: Codable {
        let previewText: String
        let fetchedAt: Date

        enum CodingKeys: String, CodingKey {
            case previewText
            case fetchedAt
        }

        init(previewText: String, fetchedAt: Date) {
            self.previewText = previewText
            self.fetchedAt = fetchedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            previewText = try container.decode(String.self, forKey: .previewText)

            if let double = try? container.decode(Double.self, forKey: .fetchedAt) {
                fetchedAt = Self.decodeDate(from: double)
            } else if let int = try? container.decode(Int.self, forKey: .fetchedAt) {
                fetchedAt = Self.decodeDate(from: Double(int))
            } else if let dateString = try? container.decode(String.self, forKey: .fetchedAt),
                      let parsed = Self.parseDateString(dateString) {
                fetchedAt = parsed
            } else {
                throw DecodingError.typeMismatch(
                    Date.self,
                    DecodingError.Context(
                        codingPath: [CodingKeys.fetchedAt],
                        debugDescription: "Unsupported timestamp format"
                    )
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(previewText, forKey: .previewText)
            try container.encode(fetchedAt.timeIntervalSince1970, forKey: .fetchedAt)
        }

        private static func parseDateString(_ string: String) -> Date? {
            if let double = Double(string) {
                return decodeDate(from: double)
            }

            let iso8601 = ISO8601DateFormatter()
            if let parsedISO = iso8601.date(from: string) {
                return parsedISO
            }

            let rfc3339 = DateFormatter()
            rfc3339.locale = Locale(identifier: "en_US_POSIX")
            rfc3339.timeZone = TimeZone(secondsFromGMT: 0)
            rfc3339.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"

            if let parsedRFC3339 = rfc3339.date(from: string) {
                return parsedRFC3339
            }

            return nil
        }

        private static let minUnixEpochForPreviewTimestamps: TimeInterval = 946684800

        private static func decodeDate(from timestamp: Double) -> Date {
            let fromEpoch = Date(timeIntervalSince1970: timestamp)
            if fromEpoch.timeIntervalSince1970 >= minUnixEpochForPreviewTimestamps {
                return fromEpoch
            }
            return Date(timeIntervalSinceReferenceDate: timestamp)
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
        static let maxDownloadBytes = 64 * 1024
        static let requestTimeout: TimeInterval = 7
        static let acceptHeader = "text/html,application/xhtml+xml"
        static let jsonAcceptHeader = "application/json,text/plain;q=0.9,*/*;q=0.8"
        static let userAgent = "Mozilla/5.0 Jin/1.0"
        static let xOEmbedEndpoint = "https://publish.twitter.com/oembed"
        static let cacheTTLSeconds: TimeInterval = 7 * 24 * 60 * 60
        static let cacheFileName = "SearchSourcePreviewCache.json"
        static let cacheFileVersion = 1
        static let blockedPathExtensions: Set<String> = [
            "jpg", "jpeg", "png", "gif", "webp", "svg", "ico",
            "pdf", "zip", "gz", "tar", "rar", "7z",
            "mp3", "wav", "ogg", "flac", "m4a",
            "mp4", "mov", "mkv", "avi", "webm"
        ]
    }

    private var cacheByURL: [String: CacheEntry] = [:]
    private var inFlightByURL: [String: Task<String?, Never>] = [:]
    private let cacheFileURL: URL?
    private let session: URLSession
    private let fileManager: FileManager
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
        cacheByURL = Self.loadCacheFromDisk(
            cacheFileURL: self.cacheFileURL,
            now: self.now
        )
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
            guard !Self.isExpired(entry.fetchedAt, now: now) else { continue }
            loaded[url] = CacheEntry(previewText: entry.previewText, fetchedAt: entry.fetchedAt)
        }

        return loaded
    }

    private func persistCacheToDisk() {
        guard let cacheFileURL else { return }
        let validEntries = cacheByURL.compactMapValues { entry -> DiskCacheEntry? in
            guard let previewText = entry.previewText else { return nil }
            guard !Self.isExpired(entry.fetchedAt, now: now()) else { return nil }
            return DiskCacheEntry(previewText: previewText, fetchedAt: entry.fetchedAt)
        }
        guard !validEntries.isEmpty else {
            try? fileManager.removeItem(at: cacheFileURL)
            return
        }

        guard let parentDir = cacheFileURL.deletingLastPathComponent() as URL? else { return }
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

    func resolvePreviewIfNeeded(rawURL: String) async -> String? {
        guard let normalizedURL = SearchURLNormalizer.normalize(rawURL) else { return nil }
        let now = now()

        if let cached = cacheByURL[normalizedURL] {
            if Self.isExpired(cached.fetchedAt, now: now) {
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
            cacheByURL[normalizedURL] = CacheEntry(previewText: preview, fetchedAt: resolvedAt)
            persistCacheToDisk()
        } else {
            cacheByURL[normalizedURL] = CacheEntry(previewText: nil, fetchedAt: resolvedAt)
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
        request.timeoutInterval = Configuration.requestTimeout
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(Configuration.acceptHeader, forHTTPHeaderField: "Accept")
        request.setValue(Configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-\(Configuration.maxDownloadBytes - 1)", forHTTPHeaderField: "Range")

        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled else { return nil }
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<400).contains(http.statusCode) else { return nil }
            guard Self.isLikelyHTML(response: http) else { return nil }

            let limitedData = Data(data.prefix(Configuration.maxDownloadBytes))
            let html = String(data: limitedData, encoding: .utf8)
                ?? String(data: limitedData, encoding: .isoLatin1)
            guard let html else { return nil }

            return SearchSourcePreviewHTMLParser.extractPreview(from: html)
        } catch {
            return nil
        }
    }

    static func canonicalXStatusURLIfNeeded(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isXHost(host) else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let statusPath: String

        if parts.count >= 3,
           isStatusPathToken(parts[1]),
           isDecimalString(parts[2]) {
            statusPath = "/\(parts[0])/status/\(parts[2])"
        } else if parts.count >= 4,
                  parts[0].caseInsensitiveCompare("i") == .orderedSame,
                  parts[1].caseInsensitiveCompare("web") == .orderedSame,
                  isStatusPathToken(parts[2]),
                  isDecimalString(parts[3]) {
            statusPath = "/i/web/status/\(parts[3])"
        } else if parts.count >= 3,
                  parts[0].caseInsensitiveCompare("i") == .orderedSame,
                  isStatusPathToken(parts[1]),
                  isDecimalString(parts[2]) {
            statusPath = "/i/web/status/\(parts[2])"
        } else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "x.com"
        components.path = statusPath
        return components.url
    }

    static func extractXPostPreview(fromOEmbedPayload data: Data) -> String? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let html = payload["html"] as? String,
           let preview = SearchSourcePreviewHTMLParser.extractPreview(from: html) {
            return preview
        }

        guard let title = payload["title"] as? String else {
            return nil
        }
        let collapsed = title
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }

    private func fetchXPostPreview(from statusURL: URL) async -> String? {
        guard var components = URLComponents(string: Configuration.xOEmbedEndpoint) else {
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
        request.timeoutInterval = Configuration.requestTimeout
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(Configuration.jsonAcceptHeader, forHTTPHeaderField: "Accept")
        request.setValue(Configuration.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled else { return nil }
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(http.statusCode) else { return nil }
            guard Self.isLikelyJSON(response: http, data: data) else { return nil }
            return Self.extractXPostPreview(fromOEmbedPayload: data)
        } catch {
            return nil
        }
    }

    private static func isXHost(_ host: String) -> Bool {
        host == "x.com"
            || host.hasSuffix(".x.com")
            || host == "twitter.com"
            || host.hasSuffix(".twitter.com")
    }

    private static func isStatusPathToken(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered == "status" || lowered == "statuses"
    }

    private static func isDecimalString(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private static func shouldAttemptPreviewFetch(for url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return false
        }

        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty, Configuration.blockedPathExtensions.contains(pathExtension) {
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

enum SearchSourcePreviewHTMLParser {
    private static let maxPreviewLength = 420
    private static let preferredMetaKeys = [
        "og:description",
        "twitter:description",
        "description",
        "dc.description",
        "sailthru.description"
    ]
    private static let metaTagRegex = try! NSRegularExpression(pattern: "(?is)<meta\\b[^>]*>")
    private static let attributeRegex = try! NSRegularExpression(
        pattern: "(?is)([a-zA-Z_:.-]+)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s\"'=<>`]+))"
    )
    private static let jsonLDScriptRegex = try! NSRegularExpression(
        pattern: "(?is)<script\\b[^>]*type\\s*=\\s*(['\"])application/ld\\+json\\1[^>]*>(.*?)</script>"
    )
    private static let scriptRegex = try! NSRegularExpression(pattern: "(?is)<script\\b[^>]*>.*?</script>")
    private static let styleRegex = try! NSRegularExpression(pattern: "(?is)<style\\b[^>]*>.*?</style>")
    private static let paragraphRegex = try! NSRegularExpression(pattern: "(?is)<p\\b[^>]*>(.*?)</p>")
    private static let titleRegex = try! NSRegularExpression(pattern: "(?is)<title\\b[^>]*>(.*?)</title>")
    private static let numericEntityRegex = try! NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);")

    private struct Candidate {
        let text: String
        let source: CandidateSource
    }

    private enum CandidateSource {
        case meta(index: Int)
        case jsonLD
        case paragraph
        case title

        var baseScore: Int {
            switch self {
            case .meta(let index):
                return 620 - (index * 24)
            case .jsonLD:
                return 540
            case .paragraph:
                return 500
            case .title:
                return 180
            }
        }
    }

    static func extractPreview(from html: String) -> String? {
        let metaValues = metaContentValues(in: html)
        let sanitizedHTML = sanitizeHTML(html)
        var candidates: [Candidate] = []

        for (index, key) in preferredMetaKeys.enumerated() {
            if let value = metaValues[key] {
                candidates.append(Candidate(text: value, source: .meta(index: index)))
            }
        }

        if let jsonLD = jsonLDDescription(in: html) {
            candidates.append(Candidate(text: jsonLD, source: .jsonLD))
        }

        if let firstParagraph = firstTagText(using: paragraphRegex, in: sanitizedHTML) {
            candidates.append(Candidate(text: firstParagraph, source: .paragraph))
        }

        if let title = firstTagText(using: titleRegex, in: sanitizedHTML) {
            candidates.append(Candidate(text: title, source: .title))
        }

        return candidates.max(by: { candidateScore($0) < candidateScore($1) })?.text
    }

    private static func sanitizeHTML(_ html: String) -> String {
        replaceMatches(of: styleRegex, in: replaceMatches(of: scriptRegex, in: html))
    }

    private static func metaContentValues(in html: String) -> [String: String] {
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        let tagMatches = metaTagRegex.matches(in: html, range: fullRange)

        var out: [String: String] = [:]
        for tagMatch in tagMatches {
            let tag = nsHTML.substring(with: tagMatch.range)
            let attributes = parseAttributes(in: tag, using: attributeRegex)
            let key = (attributes["property"] ?? attributes["name"] ?? attributes["itemprop"])?.lowercased()
            guard let key, !key.isEmpty, out[key] == nil else { continue }
            guard let normalizedContent = normalizeCandidate(attributes["content"]) else { continue }
            out[key] = normalizedContent
        }

        return out
    }

    private static func jsonLDDescription(in html: String) -> String? {
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        let matches = jsonLDScriptRegex.matches(in: html, range: fullRange)

        for match in matches where match.numberOfRanges > 2 {
            let rawJSON = nsHTML.substring(with: match.range(at: 2))
            let decodedJSON = decodeHTMLEntities(rawJSON).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !decodedJSON.isEmpty, let data = decodedJSON.data(using: .utf8) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) else { continue }

            if let description = firstStringValue(forKeys: ["description", "headline"], in: object),
               let normalized = normalizeCandidate(description) {
                return normalized
            }
        }

        return nil
    }

    private static func firstStringValue(forKeys keys: [String], in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            for key in keys {
                if let value = dictionary[key] as? String,
                   let normalized = normalizeCandidate(value) {
                    return normalized
                }
            }

            for value in dictionary.values {
                if let nested = firstStringValue(forKeys: keys, in: value) {
                    return nested
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if let nested = firstStringValue(forKeys: keys, in: item) {
                    return nested
                }
            }
        }

        return nil
    }

    private static func parseAttributes(in tag: String, using regex: NSRegularExpression) -> [String: String] {
        let nsTag = tag as NSString
        let matches = regex.matches(in: tag, range: NSRange(location: 0, length: nsTag.length))

        var attributes: [String: String] = [:]
        for match in matches where match.numberOfRanges >= 6 {
            let name = nsTag.substring(with: match.range(at: 1)).lowercased()
            let rawValueRange = [3, 4, 5]
                .map { match.range(at: $0) }
                .first(where: { $0.location != NSNotFound && $0.length > 0 })

            guard let rawValueRange else { continue }
            let rawValue = nsTag.substring(with: rawValueRange)
            attributes[name] = decodeHTMLEntities(rawValue)
        }

        return attributes
    }

    private static func firstTagText(using regex: NSRegularExpression, in html: String) -> String? {
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        guard let match = regex.firstMatch(in: html, range: fullRange), match.numberOfRanges > 1 else {
            return nil
        }

        let raw = nsHTML.substring(with: match.range(at: 1))
        return normalizeCandidate(raw)
    }

    private static func normalizeCandidate(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let withoutTags = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let decoded = decodeHTMLEntities(withoutTags)
        let collapsed = decoded
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= maxPreviewLength {
            return collapsed
        }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: maxPreviewLength)
        return String(collapsed[..<endIndex]) + "…"
    }

    private static func candidateScore(_ candidate: Candidate) -> Int {
        let wordCount = candidate.text.split(whereSeparator: \.isWhitespace).count
        let lengthScore = min(candidate.text.count, maxPreviewLength)
        let densityScore = min(wordCount * 8, 120)
        return candidate.source.baseScore + lengthScore + densityScore
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        var out = value
        let namedReplacements: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#34;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&ldquo;", "\""),
            ("&rdquo;", "\""),
            ("&lsquo;", "'"),
            ("&rsquo;", "'"),
            ("&ndash;", "-"),
            ("&mdash;", "-"),
            ("&hellip;", "…")
        ]

        for (from, to) in namedReplacements {
            out = out.replacingOccurrences(of: from, with: to)
        }

        let nsOut = out as NSString
        let matches = numericEntityRegex.matches(in: out, range: NSRange(location: 0, length: nsOut.length))

        for match in matches.reversed() where match.numberOfRanges > 1 {
            let entityValue = nsOut.substring(with: match.range(at: 1))
            let scalarValue: UInt32?
            if entityValue.hasPrefix("x") || entityValue.hasPrefix("X") {
                scalarValue = UInt32(entityValue.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(entityValue, radix: 10)
            }

            guard let scalarValue,
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }

            out = (out as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
        }

        return out
    }

    private static func replaceMatches(
        of regex: NSRegularExpression,
        in input: String
    ) -> String {
        regex.stringByReplacingMatches(
            in: input,
            range: NSRange(location: 0, length: (input as NSString).length),
            withTemplate: " "
        )
    }
}
