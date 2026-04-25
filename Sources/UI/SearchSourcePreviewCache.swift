import Foundation

struct SearchSourcePreviewCacheEntry: Sendable {
    let previewText: String?
    let fetchedAt: Date
}

enum SearchSourcePreviewConfiguration {
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

enum SearchSourcePreviewDiskCache {
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

    static func isExpired(_ date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) > SearchSourcePreviewConfiguration.cacheTTLSeconds
    }

    static func load(cacheFileURL: URL?, now: @escaping () -> Date) -> [String: SearchSourcePreviewCacheEntry] {
        var loaded: [String: SearchSourcePreviewCacheEntry] = [:]
        guard let cacheFileURL else { return loaded }
        guard let data = try? Data(contentsOf: cacheFileURL) else { return loaded }

        let decoder = JSONDecoder()
        guard
            let decoded = try? decoder.decode(DiskCachePayload.self, from: data),
            decoded.version == SearchSourcePreviewConfiguration.cacheFileVersion,
            !decoded.entries.isEmpty
        else {
            return loaded
        }

        let now = now()
        for (url, entry) in decoded.entries {
            guard !isExpired(entry.fetchedAt, now: now) else { continue }
            loaded[url] = SearchSourcePreviewCacheEntry(previewText: entry.previewText, fetchedAt: entry.fetchedAt)
        }

        return loaded
    }

    static func persist(
        cacheByURL: [String: SearchSourcePreviewCacheEntry],
        to cacheFileURL: URL?,
        fileManager: FileManager,
        now: () -> Date
    ) {
        guard let cacheFileURL else { return }
        let validEntries = cacheByURL.compactMapValues { entry -> DiskCacheEntry? in
            guard let previewText = entry.previewText else { return nil }
            guard !isExpired(entry.fetchedAt, now: now()) else { return nil }
            return DiskCacheEntry(previewText: previewText, fetchedAt: entry.fetchedAt)
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
            version: SearchSourcePreviewConfiguration.cacheFileVersion,
            entries: validEntries
        )
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return }

        try? data.write(to: cacheFileURL, options: .atomic)
    }
}
