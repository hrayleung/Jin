import SwiftUI

struct SlashCommandMCPServerItem: Identifiable, Equatable {
    let id: String
    let name: String
    let isSelected: Bool
}

struct SlashCommandMCPPopover: View {
    let servers: [SlashCommandMCPServerItem]
    let filterText: String
    let highlightedIndex: Int
    let onSelectServer: (String) -> Void
    let onDismiss: () -> Void

    private var filteredServers: [SlashCommandMCPServerItem] {
        if filterText.isEmpty {
            return servers
        }
        return servers.filter {
            $0.name.localizedCaseInsensitiveContains(filterText) ||
            $0.id.localizedCaseInsensitiveContains(filterText)
        }
    }

    var body: some View {
        let items = filteredServers
        if items.isEmpty {
            emptyState
        } else {
            serverList(items)
        }
    }

    private var emptyState: some View {
        VStack(spacing: JinSpacing.small) {
            Text("No matching MCP servers")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(JinSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    private static let scrollThreshold = 6

    @ViewBuilder
    private func serverList(_ items: [SlashCommandMCPServerItem]) -> some View {
        let needsScroll = items.count > Self.scrollThreshold

        ScrollViewReader { proxy in
            Group {
                if needsScroll {
                    ScrollView(.vertical, showsIndicators: true) {
                        listContent(items)
                    }
                    .frame(maxHeight: 240)
                } else {
                    listContent(items)
                }
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                    .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            .onChange(of: highlightedIndex) { _, _ in
                guard needsScroll else { return }
                let clamped = clampedIndex(for: items)
                if clamped < items.count {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(items[clamped].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func listContent(_ items: [SlashCommandMCPServerItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, server in
                serverRow(server, isHighlighted: index == clampedIndex(for: items))
                    .id(server.id)
                    .onTapGesture {
                        onSelectServer(server.id)
                    }
            }
        }
        .padding(.vertical, JinSpacing.xSmall)
    }

    private func clampedIndex(for items: [SlashCommandMCPServerItem]) -> Int {
        guard !items.isEmpty else { return 0 }
        return max(0, min(highlightedIndex, items.count - 1))
    }

    private func serverRow(_ server: SlashCommandMCPServerItem, isHighlighted: Bool) -> some View {
        HStack(spacing: JinSpacing.small) {
            Image(systemName: server.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(server.isSelected ? Color.accentColor : .secondary)

            Text(server.name)
                .font(.body.weight(.medium))
                .lineLimit(1)

            Text(server.id)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small)
        .background(
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .fill(isHighlighted ? JinSemanticColor.subtleSurface : Color.clear)
        )
        .padding(.horizontal, JinSpacing.xSmall)
        .contentShape(Rectangle())
    }
}

// MARK: - Slash Command Detection

enum SlashCommandDetection {
    /// Detects a `/` trigger at the end of the text that starts a word boundary.
    /// Returns the filter text after the `/`, or `nil` if no active slash command.
    static func detectFilter(in text: String) -> String? {
        // Match "/" at start of text or after whitespace, followed by non-whitespace, non-slash chars until end
        guard let range = text.range(
            of: "(?:^|(?<=\\s))/([^\\s/]*)$",
            options: .regularExpression
        ) else {
            return nil
        }
        let matched = String(text[range])
        // Drop the leading "/"
        return String(matched.dropFirst())
    }

    /// Removes the slash command token (e.g. "/filt") from the end of the text.
    static func removeSlashToken(from text: String) -> String {
        guard let range = text.range(
            of: "(?:^|(?<=\\s))/[^\\s/]*$",
            options: .regularExpression
        ) else {
            return text
        }
        var result = text
        result.removeSubrange(range)
        return result
    }

    /// Returns the ID of the highlighted server given the current filter and index.
    static func highlightedServerID(
        servers: [SlashCommandMCPServerItem],
        filterText: String,
        highlightedIndex: Int
    ) -> String? {
        let filtered = filteredServers(servers: servers, filterText: filterText)
        guard !filtered.isEmpty else { return nil }
        let clamped = max(0, min(highlightedIndex, filtered.count - 1))
        return filtered[clamped].id
    }

    static func filteredServers(
        servers: [SlashCommandMCPServerItem],
        filterText: String
    ) -> [SlashCommandMCPServerItem] {
        if filterText.isEmpty { return servers }
        return servers.filter {
            $0.name.localizedCaseInsensitiveContains(filterText) ||
            $0.id.localizedCaseInsensitiveContains(filterText)
        }
    }

    static func filteredCount(
        servers: [SlashCommandMCPServerItem],
        filterText: String
    ) -> Int {
        filteredServers(servers: servers, filterText: filterText).count
    }
}
