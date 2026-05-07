import Foundation

enum NPMRCUtils {
    static func parseAssignments(from contents: String) -> [String: String] {
        var assignments: [String: String] = [:]

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            guard let (key, value) = parseLine(String(rawLine)) else { continue }
            assignments[key] = value
        }

        return assignments
    }

    static func safeEntriesToInherit(from contents: String) -> [String: String] {
        var safe: [String: String] = [:]

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            guard let (key, value) = parseLine(String(rawLine)) else { continue }
            guard shouldInheritKey(key) else { continue }
            safe[key] = value
        }

        return safe
    }

    private static func parseLine(_ line: String) -> (key: String, value: String)? {
        guard let trimmed = line.trimmedNonEmpty else { return nil }
        if trimmed.hasPrefix("#") || trimmed.hasPrefix(";") { return nil }

        let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        guard let key = String(parts[0]).trimmedNonEmpty else { return nil }
        let value = String(parts[1]).trimmed
        return (key, value)
    }

    private static func shouldInheritKey(_ key: String) -> Bool {
        let lower = key.lowercased()

        // Avoid credentials and per-registry auth configs.
        if lower.hasPrefix("//") { return false }
        if lower.contains("_auth") { return false }
        if lower.contains("token") { return false }
        if lower.contains("password") { return false }
        if lower.contains("username") { return false }

        // Jin manages these for isolation.
        if ["prefix", "cache", "fund", "update-notifier", "progress"].contains(lower) { return false }

        // Safe network/proxy/registry settings.
        let allowed = Set([
            "ca",
            "cafile",
            "fetch-retries",
            "fetch-retry-factor",
            "fetch-retry-maxtimeout",
            "fetch-retry-mintimeout",
            "https-proxy",
            "network-timeout",
            "noproxy",
            "proxy",
            "registry",
            "strict-ssl",
        ])

        if allowed.contains(lower) { return true }

        // Support scoped registries, e.g. "@my-scope:registry=https://..."
        if lower.hasSuffix(":registry") { return true }

        return false
    }
}
