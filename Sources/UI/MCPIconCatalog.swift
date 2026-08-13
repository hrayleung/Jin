import AppKit

struct MCPIcon: Identifiable, Hashable {
    let id: String
    let lightResourceName: String
    let darkResourceName: String

    func localPNGImage(useDarkMode: Bool) -> NSImage? {
        if let preferredImage = cachedPNGImage(appearance: useDarkMode ? "dark" : "light") {
            return preferredImage
        }

        if useDarkMode {
            return cachedPNGImage(appearance: "light")
        }
        return nil
    }

    private func cachedPNGImage(appearance: String) -> NSImage? {
        let resourceName = appearance == "dark" ? darkResourceName : lightResourceName
        let cacheKey = "mcp/\(appearance)/\(resourceName)"

        return MCPIconCatalog.cachedImage(forKey: cacheKey) {
            guard let resourceURL = JinResourceBundle.url(
                forResource: resourceName,
                withExtension: "png",
                subdirectory: "mcpIcons"
            ) ?? JinResourceBundle.url(
                forResource: resourceName,
                withExtension: "png"
            ) else {
                return nil
            }
            // Bundled icons ship at up to 2048px but render at 18-40 pt;
            // decode at icon size so browsing the picker doesn't materialize
            // full-resolution bitmaps.
            return ImageDownsampler.image(
                at: resourceURL,
                maxPixelSize: MCPIconCatalog.maxIconPixelSize
            )
        }
    }
}

enum MCPIconCatalog {
    static let defaultIconID = "mcp"

    /// Largest render size is ~40 pt; 128 px covers @2x with headroom.
    static let maxIconPixelSize = 128

    // Entries are icon-sized (~65 KB) after downsampling, so the whole
    // catalog stays warm well under the cost ceiling.
    private static let imageCache = LockedNSImageCache(
        countLimit: 256,
        totalCostLimit: 16 * 1024 * 1024
    )

    static let all: [MCPIcon] = loadBundledIcons()

    private static let iconByLowercasedID: [String: MCPIcon] = Dictionary(
        uniqueKeysWithValues: all.map { icon in
            (icon.id.lowercased(), icon)
        }
    )

    static func icon(forID id: String?) -> MCPIcon? {
        guard let id = id?.trimmedNonEmpty else { return nil }
        return iconByLowercasedID[id.lowercased()]
    }

    static func resolvedIconID(for id: String?) -> String {
        guard let resolved = icon(forID: id)?.id else {
            return defaultIconID
        }
        return resolved
    }

    static func cachedImage(forKey key: String, loader: () -> NSImage?) -> NSImage? {
        let nsKey = key as NSString
        if let cached = imageCache.object(forKey: nsKey) {
            return cached
        }

        guard let image = loader() else {
            return nil
        }

        imageCache.setObject(image, forKey: nsKey, cost: ImageDownsampler.estimatedBitmapCost(of: image))
        return image
    }

    private static func loadBundledIcons() -> [MCPIcon] {
        guard let urls = JinResourceBundle.bundle?.urls(forResourcesWithExtension: "png", subdirectory: "mcpIcons"),
              !urls.isEmpty else {
            return fallbackIcons()
        }

        var variantsByID: [String: (light: String?, dark: String?)] = [:]

        for url in urls {
            let resourceName = url.deletingPathExtension().lastPathComponent
            let lowercased = resourceName.lowercased()

            if lowercased.hasSuffix("_light") {
                let id = String(lowercased.dropLast("_light".count))
                var variants = variantsByID[id] ?? (nil, nil)
                variants.light = resourceName
                variantsByID[id] = variants
            } else if lowercased.hasSuffix("_dark") {
                let id = String(lowercased.dropLast("_dark".count))
                var variants = variantsByID[id] ?? (nil, nil)
                variants.dark = resourceName
                variantsByID[id] = variants
            }
        }

        var icons = variantsByID.compactMap { id, variants -> MCPIcon? in
            let light = variants.light ?? variants.dark
            let dark = variants.dark ?? variants.light
            guard let light, let dark else { return nil }
            return MCPIcon(id: id, lightResourceName: light, darkResourceName: dark)
        }

        if !icons.contains(where: { $0.id.caseInsensitiveCompare(defaultIconID) == .orderedSame }) {
            icons.append(MCPIcon(id: defaultIconID, lightResourceName: "mcp_light", darkResourceName: "mcp_dark"))
        }

        icons.sort { lhs, rhs in
            if lhs.id.caseInsensitiveCompare(defaultIconID) == .orderedSame { return true }
            if rhs.id.caseInsensitiveCompare(defaultIconID) == .orderedSame { return false }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }

        return icons
    }

    private static func fallbackIcons() -> [MCPIcon] {
        [
            MCPIcon(id: "mcp", lightResourceName: "mcp_light", darkResourceName: "mcp_dark"),
            MCPIcon(id: "exa", lightResourceName: "exa_light", darkResourceName: "exa_dark"),
            MCPIcon(id: "github", lightResourceName: "github_light", darkResourceName: "github_dark")
        ]
    }
}

extension MCPServerConfigEntity {
    var resolvedMCPIconID: String {
        MCPIconCatalog.resolvedIconID(for: iconID)
    }
}
