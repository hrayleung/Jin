import Foundation

/// MCP tool calling controls (app-provided tools via MCP servers).
struct MCPToolsControls: Codable {
    var enabled: Bool
    /// Optional allowlist of MCP server IDs for this conversation. `nil` means "all enabled servers".
    var enabledServerIDs: [String]?

    init(enabled: Bool = true, enabledServerIDs: [String]? = nil) {
        self.enabled = enabled
        self.enabledServerIDs = enabledServerIDs
    }
}

/// User location for localizing Anthropic web search results.
struct WebSearchUserLocation: Codable, Equatable {
    var city: String?
    var region: String?
    var country: String?      // 2-letter ISO code
    var timezone: String?     // IANA timezone

    var isEmpty: Bool {
        [city, region, country, timezone].allSatisfy { $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true }
    }
}

/// Built-in web search controls (provider-native).
struct WebSearchControls: Codable {
    var enabled: Bool
    var contextSize: WebSearchContextSize?
    var sources: [WebSearchSource]?
    // Anthropic-specific fields:
    var maxUses: Int?
    var allowedDomains: [String]?
    var blockedDomains: [String]?
    var userLocation: WebSearchUserLocation?
    var dynamicFiltering: Bool?

    init(
        enabled: Bool = false,
        contextSize: WebSearchContextSize? = nil,
        sources: [WebSearchSource]? = nil,
        maxUses: Int? = nil,
        allowedDomains: [String]? = nil,
        blockedDomains: [String]? = nil,
        userLocation: WebSearchUserLocation? = nil,
        dynamicFiltering: Bool? = nil
    ) {
        self.enabled = enabled
        self.contextSize = contextSize
        self.sources = sources
        self.maxUses = maxUses
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
        self.userLocation = userLocation
        self.dynamicFiltering = dynamicFiltering
    }
}

enum WebSearchContextSize: String, Codable, CaseIterable {
    case low, medium, high

    var displayName: String { rawValue.capitalized }
}

enum WebSearchSource: String, Codable, CaseIterable {
    case web, x

    var displayName: String {
        switch self {
        case .web: return "Web"
        case .x: return "X"
        }
    }
}

/// Built-in web search providers (non-provider-native).
enum SearchPluginProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case exa
    case brave
    case jina
    case firecrawl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .exa: return "Exa"
        case .brave: return "Brave Search"
        case .jina: return "Jina Search"
        case .firecrawl: return "Firecrawl"
        }
    }

    var shortBadge: String {
        switch self {
        case .exa: return "Exa"
        case .brave: return "Br"
        case .jina: return "Jina"
        case .firecrawl: return "FC"
        }
    }
}

enum ExaSearchType: String, Codable, CaseIterable, Sendable {
    case auto
    case keyword
    case neural
}

/// Built-in web search controls (app plugin-backed).
struct SearchPluginControls: Codable, Sendable {
    var preferJinSearch: Bool?
    var provider: SearchPluginProvider?
    var maxResults: Int?
    var recencyDays: Int?
    var includeRawContent: Bool?
    var fetchPageContent: Bool?

    // Exa-specific
    var exaSearchType: ExaSearchType?
    var exaUseAutoprompt: Bool?

    // Brave-specific
    var braveCountry: String?
    var braveLanguage: String?
    var braveSafesearch: String?

    // Firecrawl-specific
    var firecrawlExtractContent: Bool?

    init(
        preferJinSearch: Bool? = nil,
        provider: SearchPluginProvider? = nil,
        maxResults: Int? = nil,
        recencyDays: Int? = nil,
        includeRawContent: Bool? = nil,
        fetchPageContent: Bool? = nil,
        exaSearchType: ExaSearchType? = nil,
        exaUseAutoprompt: Bool? = nil,
        braveCountry: String? = nil,
        braveLanguage: String? = nil,
        braveSafesearch: String? = nil,
        firecrawlExtractContent: Bool? = nil
    ) {
        self.preferJinSearch = preferJinSearch
        self.provider = provider
        self.maxResults = maxResults
        self.recencyDays = recencyDays
        self.includeRawContent = includeRawContent
        self.fetchPageContent = fetchPageContent
        self.exaSearchType = exaSearchType
        self.exaUseAutoprompt = exaUseAutoprompt
        self.braveCountry = braveCountry
        self.braveLanguage = braveLanguage
        self.braveSafesearch = braveSafesearch
        self.firecrawlExtractContent = firecrawlExtractContent
    }
}

/// UI-only enum for Anthropic domain filtering mode selection.
enum AnthropicDomainFilterMode: Hashable {
    case none
    case allowed
    case blocked
}

/// Shared parsing/validation helpers for Anthropic web search domain filters.
enum AnthropicWebSearchDomainUtils {
    private static let separators = CharacterSet.newlines.union(CharacterSet(charactersIn: ","))

    static func splitInput(_ raw: String) -> [String] {
        raw.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func normalizedDomains(_ domains: [String]?) -> [String] {
        guard let domains else { return [] }

        var seen: Set<String> = []
        var normalized: [String] = []
        normalized.reserveCapacity(domains.count)

        for domain in domains {
            let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                normalized.append(trimmed)
            }
        }

        return normalized
    }

    static func firstValidationError(in domains: [String]) -> String? {
        for domain in domains {
            if let error = validationError(for: domain) {
                return error
            }
        }
        return nil
    }

    static func validationError(for domain: String) -> String? {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Domain entries cannot be empty."
        }

        if trimmed.contains("://") {
            return "Domain '\(trimmed)' must not include http:// or https://."
        }

        if trimmed.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) {
            return "Domain '\(trimmed)' must not include whitespace."
        }

        let firstSlash = trimmed.firstIndex(of: "/")
        let host = firstSlash.map { String(trimmed[..<$0]) } ?? trimmed
        if host.isEmpty {
            return "Domain '\(trimmed)' is missing a hostname."
        }
        if host.contains("*") {
            return "Domain '\(trimmed)' uses '*' in the hostname. Wildcards are only allowed in paths."
        }

        let wildcardCount = trimmed.filter { $0 == "*" }.count
        if wildcardCount > 1 {
            return "Domain '\(trimmed)' can contain only one wildcard '*'."
        }

        if wildcardCount == 1 {
            guard let slashIndex = firstSlash,
                  let wildcardIndex = trimmed.firstIndex(of: "*"),
                  wildcardIndex > slashIndex else {
                return "Domain '\(trimmed)' must place '*' in the path after the hostname."
            }
        }

        return nil
    }
}

/// How to process PDF attachments before sending to the model.
enum PDFProcessingMode: String, Codable, CaseIterable {
    case native
    case mistralOCR
    case deepSeekOCR
    case macOSExtract

    var displayName: String {
        switch self {
        case .native: return "Native"
        case .mistralOCR: return "Mistral OCR"
        case .deepSeekOCR: return "DeepSeek OCR (DeepInfra)"
        case .macOSExtract: return "macOS Extract"
        }
    }
}
