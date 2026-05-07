import Foundation

enum SearchRedirectURLCacheStore {
    struct Entry: Equatable, Sendable {
        let resolvedURL: String?
        let resolvedAt: Date
    }

    private struct DiskEntry: Codable {
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

    private struct DiskPayload: Codable {
        let version: Int
        let entries: [String: DiskEntry]

        init(version: Int = fileVersion, entries: [String: DiskEntry]) {
            self.version = version
            self.entries = entries
        }
    }

    private static let cacheTTLSeconds: TimeInterval = 7 * 24 * 60 * 60
    private static let fileVersion = 1

    static func isExpired(_ date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) > cacheTTLSeconds
    }

    static func load(from cacheFileURL: URL?, now: Date) -> [String: Entry] {
        guard let cacheFileURL,
              let data = try? Data(contentsOf: cacheFileURL),
              let decoded = try? JSONDecoder().decode(DiskPayload.self, from: data),
              decoded.version == fileVersion,
              !decoded.entries.isEmpty else {
            return [:]
        }

        return decoded.entries.reduce(into: [:]) { loaded, pair in
            guard !isExpired(pair.value.resolvedAt, now: now) else { return }
            loaded[pair.key] = Entry(
                resolvedURL: pair.value.resolvedURL,
                resolvedAt: pair.value.resolvedAt
            )
        }
    }

    static func persist(
        _ entries: [String: Entry],
        to cacheFileURL: URL?,
        fileManager: FileManager,
        now: Date
    ) {
        guard let cacheFileURL else { return }

        let validEntries = entries.compactMapValues { entry -> DiskEntry? in
            guard !isExpired(entry.resolvedAt, now: now) else { return nil }
            return DiskEntry(resolvedURL: entry.resolvedURL, resolvedAt: entry.resolvedAt)
        }

        guard !validEntries.isEmpty else {
            try? fileManager.removeItem(at: cacheFileURL)
            return
        }

        let parentDir = cacheFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let payload = DiskPayload(entries: validEntries)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: cacheFileURL, options: .atomic)
    }
}
