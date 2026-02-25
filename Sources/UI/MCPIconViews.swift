import AppKit
import SwiftUI

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
            return NSImage(contentsOf: resourceURL)
        }
    }
}

enum MCPIconCatalog {
    private final class ImageCache: @unchecked Sendable {
        private let lock = NSLock()
        private let cache: NSCache<NSString, NSImage> = {
            let cache = NSCache<NSString, NSImage>()
            cache.countLimit = 64
            return cache
        }()

        func object(forKey key: NSString) -> NSImage? {
            lock.lock()
            defer { lock.unlock() }
            return cache.object(forKey: key)
        }

        func setObject(_ image: NSImage, forKey key: NSString) {
            lock.lock()
            defer { lock.unlock() }
            cache.setObject(image, forKey: key)
        }
    }

    static let defaultIconID = "mcp"

    private static let imageCache = ImageCache()

    static let all: [MCPIcon] = loadBundledIcons()

    private static let iconByLowercasedID: [String: MCPIcon] = Dictionary(
        uniqueKeysWithValues: all.map { icon in
            (icon.id.lowercased(), icon)
        }
    )

    static func icon(forID id: String?) -> MCPIcon? {
        guard let id else { return nil }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return iconByLowercasedID[trimmed.lowercased()]
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

        imageCache.setObject(image, forKey: nsKey)
        return image
    }

    private static func loadBundledIcons() -> [MCPIcon] {
        guard let urls = JinResourceBundle.bundle?.urls(forResourcesWithExtension: "png", subdirectory: nil),
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

struct MCPIconView: View {
    @Environment(\.colorScheme) private var colorScheme

    let iconID: String?
    var fallbackSystemName: String = "server.rack"
    var size: CGFloat = 18

    var body: some View {
        if let iconImage {
            iconImage
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            fallbackIcon
        }
    }

    private var iconImage: Image? {
        guard let icon = MCPIconCatalog.icon(forID: iconID),
              let nsImage = icon.localPNGImage(useDarkMode: colorScheme == .dark) else {
            return nil
        }
        return Image(nsImage: nsImage)
    }

    private var fallbackIcon: some View {
        Image(systemName: fallbackSystemName)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.8, height: size * 0.8)
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}

struct MCPIconPickerField: View {
    @Binding var selectedIconID: String?
    let defaultIconID: String

    @State private var isPickerPresented = false

    private var normalizedSelectedIconID: String? {
        let trimmed = selectedIconID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        if trimmed.caseInsensitiveCompare(defaultIconID) == .orderedSame {
            return nil
        }
        return trimmed
    }

    private var activeIconID: String {
        if let normalizedSelectedIconID {
            return normalizedSelectedIconID
        }
        return defaultIconID
    }

    var body: some View {
        HStack(alignment: .center, spacing: JinSpacing.medium) {
            Text("Icon")

            Spacer()

            Button {
                isPickerPresented = true
            } label: {
                HStack(spacing: JinSpacing.small) {
                    MCPIconView(iconID: activeIconID, size: 18)
                        .frame(width: 22, height: 22)
                        .jinSurface(.subtle, cornerRadius: JinRadius.small)

                    Text(iconLabel)
                        .font(.body)
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, JinSpacing.medium - 2)
                .padding(.vertical, JinSpacing.xSmall + 2)
                .jinSurface(.neutral, cornerRadius: JinRadius.small)
            }
            .buttonStyle(.plain)
            .help("Choose MCP server icon")
            .sheet(isPresented: $isPickerPresented) {
                MCPIconPickerSheet(
                    selectedIconID: $selectedIconID,
                    defaultIconID: defaultIconID
                )
            }
        }
    }

    private var iconLabel: String {
        if let normalizedSelectedIconID {
            return normalizedSelectedIconID
        }

        return "Default"
    }
}

private struct MCPIconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedIconID: String?
    let defaultIconID: String

    @State private var searchText = ""
    @State private var draftIconID: String?

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 88), spacing: JinSpacing.medium)
    ]

    private var selectableIcons: [MCPIcon] {
        MCPIconCatalog.all.filter { icon in
            icon.id.caseInsensitiveCompare(defaultIconID) != .orderedSame
        }
    }

    private var normalizedDraftIconID: String? {
        let trimmed = draftIconID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        if trimmed.caseInsensitiveCompare(defaultIconID) == .orderedSame {
            return nil
        }
        return trimmed
    }

    private var filteredIcons: [MCPIcon] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return selectableIcons }
        return selectableIcons.filter { icon in
            icon.id.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: JinSpacing.medium) {
                TextField("Search MCP icon", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: JinSpacing.medium) {
                        defaultCell

                        ForEach(filteredIcons) { icon in
                            iconCell(icon: icon)
                        }
                    }
                    .padding(.vertical, JinSpacing.small)
                }
                .jinSurface(.raised, cornerRadius: JinRadius.medium)
            }
            .padding(JinSpacing.medium)
            .navigationTitle("MCP Icons")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selectedIconID = draftIconID
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 460)
        .onAppear {
            draftIconID = selectedIconID
        }
    }

    private var defaultCell: some View {
        let isSelected = normalizedDraftIconID == nil

        return Button {
            draftIconID = nil
        } label: {
            VStack(spacing: JinSpacing.xSmall) {
                ZStack(alignment: .bottomTrailing) {
                    MCPIconView(iconID: defaultIconID, size: 26)
                        .frame(width: 40, height: 40)
                        .jinSurface(.subtle, cornerRadius: JinRadius.medium)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .font(.system(size: 13, weight: .bold))
                            .offset(x: 4, y: 4)
                    }
                }

                Text("Default")
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, JinSpacing.small)
            .padding(.horizontal, JinSpacing.xSmall)
            .jinSurface(isSelected ? .selected : .neutral, cornerRadius: JinRadius.medium)
        }
        .buttonStyle(.plain)
    }

    private func iconCell(icon: MCPIcon) -> some View {
        let isSelected = normalizedDraftIconID?.caseInsensitiveCompare(icon.id) == .orderedSame

        return Button {
            draftIconID = icon.id
        } label: {
            VStack(spacing: JinSpacing.xSmall) {
                ZStack(alignment: .bottomTrailing) {
                    MCPIconView(iconID: icon.id, size: 26)
                        .frame(width: 40, height: 40)
                        .jinSurface(.subtle, cornerRadius: JinRadius.medium)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .font(.system(size: 13, weight: .bold))
                            .offset(x: 4, y: 4)
                    }
                }

                Text(icon.id)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, JinSpacing.small)
            .padding(.horizontal, JinSpacing.xSmall)
            .jinSurface(isSelected ? .selected : .neutral, cornerRadius: JinRadius.medium)
        }
        .buttonStyle(.plain)
    }
}

extension MCPServerConfigEntity {
    var resolvedMCPIconID: String {
        MCPIconCatalog.resolvedIconID(for: iconID)
    }
}
