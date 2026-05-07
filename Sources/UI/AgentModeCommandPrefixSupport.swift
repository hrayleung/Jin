import Foundation

enum AgentModeCommandPrefixSupport {
    static func normalizedPrefix(_ prefix: String) -> String? {
        prefix.trimmedNonEmpty
    }

    static func canAddPrefix(_ prefix: String) -> Bool {
        normalizedPrefix(prefix) != nil
    }

    static func addingPrefix(_ prefix: String, to prefixes: [String]) -> [String] {
        guard let normalized = normalizedPrefix(prefix) else { return prefixes }
        guard !prefixes.contains(normalized) else { return prefixes }
        return prefixes + [normalized]
    }

    static func removingPrefix(_ prefix: String, from prefixes: [String]) -> [String] {
        prefixes.filter { $0 != prefix }
    }

    static func shouldShowResetToDefaults(
        currentPrefixes: [String],
        defaultPrefixes: [String]
    ) -> Bool {
        currentPrefixes != defaultPrefixes
    }
}
