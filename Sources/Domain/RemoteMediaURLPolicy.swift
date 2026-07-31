import Foundation

enum RemoteMediaURLPolicy {
    static let maximumAutomaticFetchBytes = 25 * 1024 * 1024
    /// Videos legitimately run far larger than images (a 4K Veo clip is
    /// ~100-200 MB), but an automatic fetch still needs a ceiling — video
    /// downloads stream to disk, so this bounds disk, not RAM.
    static let maximumAutomaticVideoFetchBytes = 512 * 1024 * 1024

    static func isAllowedForAutomaticFetch(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host(percentEncoded: false)?.trimmedLowercased,
              !host.isEmpty,
              !isBlockedHost(host) else {
            return false
        }
        return true
    }

    private static func isBlockedHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if normalized == "localhost" || normalized.hasSuffix(".localhost") {
            return true
        }
        if normalized.range(of: ":") != nil {
            return isBlockedIPv6Literal(normalized)
        }
        if let octets = ipv4Octets(from: normalized) {
            return isBlockedIPv4Literal(octets)
        }
        if !normalized.contains(".") {
            return true
        }
        return false
    }

    private static func ipv4Octets(from host: String) -> [Int]? {
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return nil }

        var octets: [Int] = []
        for component in components {
            guard !component.isEmpty,
                  component.allSatisfy({ $0.isNumber }),
                  let value = Int(component),
                  (0...255).contains(value) else {
                return nil
            }
            octets.append(value)
        }
        return octets
    }

    private static func isBlockedIPv4Literal(_ octets: [Int]) -> Bool {
        let first = octets[0]
        let second = octets[1]

        switch first {
        case 0, 10, 127:
            return true
        case 100:
            return (64...127).contains(second)
        case 169:
            return second == 254
        case 172:
            return (16...31).contains(second)
        case 192:
            return second == 0 || second == 168
        case 198:
            return second == 18 || second == 19 || second == 51
        case 203:
            return second == 0
        case 224...255:
            return true
        default:
            return false
        }
    }

    private static func isBlockedIPv6Literal(_ host: String) -> Bool {
        let literal = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let lowercase = literal.lowercased()
        if lowercase == "::" || lowercase == "::1" {
            return true
        }
        if lowercase.hasPrefix("fc") || lowercase.hasPrefix("fd") {
            return true
        }
        if lowercase.hasPrefix("fe8") || lowercase.hasPrefix("fe9") || lowercase.hasPrefix("fea") || lowercase.hasPrefix("feb") {
            return true
        }
        if lowercase.hasPrefix("ff") {
            return true
        }
        if lowercase.hasPrefix("::ffff:"),
           let octets = ipv4Octets(from: String(lowercase.dropFirst("::ffff:".count))) {
            return isBlockedIPv4Literal(octets)
        }
        return false
    }
}
