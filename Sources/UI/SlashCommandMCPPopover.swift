import SwiftUI

struct SlashCommandMCPPopover: View {
    let servers: [SlashCommandMCPServerItem]
    let filterText: String
    let highlightedIndex: Int
    let onSelectServer: (String) -> Void
    let onDismiss: () -> Void

    private var filteredServers: [SlashCommandMCPServerItem] {
        SlashCommandDetection.filteredServers(servers: servers, filterText: filterText)
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
        .jinAdaptiveBackground(RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                .stroke(JinSemanticColor.borderEmphasized, lineWidth: JinStrokeWidth.hairline)
        )
        .shadow(color: JinSemanticColor.shadowElevated, radius: 12, x: 0, y: 4)
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
            .jinAdaptiveBackground(RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                    .stroke(JinSemanticColor.borderEmphasized, lineWidth: JinStrokeWidth.hairline)
            )
            .shadow(color: JinSemanticColor.shadowElevated, radius: 12, x: 0, y: 4)
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
