import Collections
import Foundation

struct CodexWorkingDirectoryPreset: Identifiable, Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
    }

    var id: UUID
    var name: String
    var path: String

    init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
    }
}

enum CodexWorkingDirectoryPresetsStore {
    static func load(defaults: UserDefaults = .standard) -> [CodexWorkingDirectoryPreset] {
        guard let raw = defaults.string(forKey: AppPreferenceKeys.codexWorkingDirectoryPresetsJSON),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([CodexWorkingDirectoryPreset].self, from: data) else {
            return []
        }

        let normalized = normalized(decoded)
        if normalized != decoded {
            persist(normalized, defaults: defaults, announceChange: false)
        }
        return normalized
    }

    static func save(_ presets: [CodexWorkingDirectoryPreset], defaults: UserDefaults = .standard) {
        persist(normalized(presets), defaults: defaults, announceChange: true)
    }

    static func normalized(_ presets: [CodexWorkingDirectoryPreset]) -> [CodexWorkingDirectoryPreset] {
        var seenPaths = OrderedSet<String>()
        var result: [CodexWorkingDirectoryPreset] = []
        result.reserveCapacity(presets.count)

        for preset in presets {
            guard let normalizedPath = normalizedDirectoryPath(from: preset.path, requireExistingDirectory: false) else {
                continue
            }

            let dedupeKey = normalizedPath.lowercased()
            guard !seenPaths.contains(dedupeKey) else { continue }
            seenPaths.append(dedupeKey)

            let trimmedName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackName = URL(fileURLWithPath: normalizedPath, isDirectory: true).lastPathComponent
            let name = trimmedName.isEmpty ? fallbackName : trimmedName
            guard !name.isEmpty else { continue }

            result.append(
                CodexWorkingDirectoryPreset(
                    id: preset.id,
                    name: name,
                    path: normalizedPath
                )
            )
        }

        return result
    }

    static func normalizedDirectoryPath(
        from raw: String,
        requireExistingDirectory: Bool = true
    ) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }

        if requireExistingDirectory {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }
        }

        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
    }

    private static func persist(
        _ presets: [CodexWorkingDirectoryPreset],
        defaults: UserDefaults,
        announceChange: Bool
    ) {
        guard let data = try? JSONEncoder().encode(presets),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        defaults.set(json, forKey: AppPreferenceKeys.codexWorkingDirectoryPresetsJSON)
        guard announceChange else { return }
        NotificationCenter.default.post(name: .codexWorkingDirectoryPresetsDidChange, object: nil)
    }
}
