import Foundation

enum MCPIconPickerSupport {
    static func normalizedCustomIconID(_ id: String?, defaultIconID: String) -> String? {
        guard let trimmed = id?.trimmedNonEmpty else { return nil }
        if trimmed.caseInsensitiveCompare(defaultIconID) == .orderedSame {
            return nil
        }
        return trimmed
    }

    static func activeIconID(selectedIconID: String?, defaultIconID: String) -> String {
        normalizedCustomIconID(selectedIconID, defaultIconID: defaultIconID) ?? defaultIconID
    }

    static func displayLabel(selectedIconID: String?, defaultIconID: String) -> String {
        guard let iconID = normalizedCustomIconID(selectedIconID, defaultIconID: defaultIconID) else {
            return "Default"
        }
        return displayName(for: iconID)
    }

    static func displayName(for iconID: String) -> String {
        switch iconID.lowercased() {
        case "tinyfish": return "TinyFish"
        case "context7": return "Context7"
        case "playwright": return "Playwright"
        case "linear": return "Linear"
        case "slack": return "Slack"
        case "stripe": return "Stripe"
        case "sentry": return "Sentry"
        case "supabase": return "Supabase"
        case "huggingface": return "Hugging Face"
        case "cloudflare": return "Cloudflare"
        case "brave": return "Brave"
        case "jina": return "Jina"
        case "morph": return "Morph"
        case "github": return "GitHub"
        case "notion": return "Notion"
        case "figma": return "Figma"
        case "exa": return "Exa"
        case "tavily": return "Tavily"
        case "firecrawl": return "Firecrawl"
        case "perplexity": return "Perplexity"
        case "parallel": return "Parallel"
        case "elevenlabs": return "ElevenLabs"
        default: return iconID
        }
    }

    static func selectableIcons(from icons: [MCPIcon], defaultIconID: String) -> [MCPIcon] {
        icons.filter { icon in
            icon.id.caseInsensitiveCompare(defaultIconID) != .orderedSame
        }
    }

    static func filteredIcons(
        from icons: [MCPIcon],
        searchText: String,
        defaultIconID: String
    ) -> [MCPIcon] {
        let selectableIcons = selectableIcons(from: icons, defaultIconID: defaultIconID)
        guard let query = searchText.trimmedNonEmpty?.lowercased() else { return selectableIcons }

        return selectableIcons.filter { icon in
            icon.id.lowercased().contains(query)
                || displayName(for: icon.id).lowercased().contains(query)
        }
    }

    static func isDefaultSelected(_ iconID: String?, defaultIconID: String) -> Bool {
        normalizedCustomIconID(iconID, defaultIconID: defaultIconID) == nil
    }

    static func isSelected(icon: MCPIcon, selectedIconID: String?, defaultIconID: String) -> Bool {
        normalizedCustomIconID(selectedIconID, defaultIconID: defaultIconID)?
            .caseInsensitiveCompare(icon.id) == .orderedSame
    }
}
