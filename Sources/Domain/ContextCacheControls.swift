import Foundation

/// Unified context/prompt cache controls.
struct ContextCacheControls: Codable, Equatable {
    var mode: ContextCacheMode
    var strategy: ContextCacheStrategy?
    var ttl: ContextCacheTTL?
    /// OpenAI-compatible stable prompt cache key.
    var cacheKey: String?
    /// xAI conversation-level cache key (`x-grok-conv-id`).
    var conversationID: String?
    /// Google explicit cache resource name (e.g., `cachedContents/abc123`).
    var cachedContentName: String?
    var minTokensThreshold: Int?

    init(
        mode: ContextCacheMode = .implicit,
        strategy: ContextCacheStrategy? = nil,
        ttl: ContextCacheTTL? = nil,
        cacheKey: String? = nil,
        conversationID: String? = nil,
        cachedContentName: String? = nil,
        minTokensThreshold: Int? = nil
    ) {
        self.mode = mode
        self.strategy = strategy
        self.ttl = ttl
        self.cacheKey = cacheKey
        self.conversationID = conversationID
        self.cachedContentName = cachedContentName
        self.minTokensThreshold = minTokensThreshold
    }

    var isEnabled: Bool {
        mode != .off
    }
}

enum ContextCacheMode: String, Codable, CaseIterable {
    case off
    case implicit
    case explicit

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .implicit: return "Implicit"
        case .explicit: return "Explicit"
        }
    }
}

enum ContextCacheStrategy: String, Codable, CaseIterable {
    case systemOnly
    case systemAndTools
    case prefixWindow

    var displayName: String {
        switch self {
        case .systemOnly: return "System only"
        case .systemAndTools: return "System + tools"
        case .prefixWindow: return "Prefix window"
        }
    }
}

enum ContextCacheTTL: Codable, Equatable {
    case providerDefault
    case minutes5
    case hour1
    case customSeconds(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .customSeconds(max(1, intValue))
            return
        }

        let raw = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch raw {
        case "", "default", "provider_default", "providerdefault":
            self = .providerDefault
        case "5m", "5min", "5mins", "minutes5":
            self = .minutes5
        case "1h", "60m", "hour1":
            self = .hour1
        default:
            if raw.hasPrefix("custom:"),
               let value = Int(raw.dropFirst("custom:".count).trimmingCharacters(in: .whitespacesAndNewlines)),
               value > 0 {
                self = .customSeconds(value)
            } else {
                self = .providerDefault
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .providerDefault:
            try container.encode("default")
        case .minutes5:
            try container.encode("5m")
        case .hour1:
            try container.encode("1h")
        case .customSeconds(let seconds):
            try container.encode("custom:\(max(1, seconds))")
        }
    }

    var displayName: String {
        switch self {
        case .providerDefault: return "Provider default"
        case .minutes5: return "5 minutes"
        case .hour1: return "1 hour"
        case .customSeconds(let seconds): return "\(seconds)s"
        }
    }

    /// Provider wire format for TTL when supported.
    var providerTTLString: String? {
        switch self {
        case .providerDefault: return nil
        case .minutes5: return "5m"
        case .hour1: return "1h"
        case .customSeconds(let seconds): return "\(max(1, seconds))s"
        }
    }
}
