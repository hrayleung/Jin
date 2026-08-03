import SwiftUI

// MARK: - Multi-tool summary row

struct MCPToolTimelineCollapsedSummaryRow: View {
    let title: String
    let serverIDs: [String]
    let iconIDByServerID: [String: String]
    let isStreaming: Bool
    let runningCount: Int
    let compactStatusBadges: [MCPToolTimelineSupport.CompactStatusBadge]
    let durationText: String?
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: JinSpacing.small) {
                MCPToolTimelineSummaryIconStack(
                    serverIDs: serverIDs,
                    iconIDByServerID: iconIDByServerID
                )

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(JinSemanticColor.textSecondary)
                    .lineLimit(1)

                MCPToolTimelineCompactStatusView(badges: compactStatusBadges)

                if let durationText, runningCount == 0 {
                    Text(durationText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(JinSemanticColor.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                if isStreaming, runningCount > 0 {
                    ProgressView()
                        .controlSize(.mini)
                }

                Spacer(minLength: 0)

                JinDisclosureChevron(
                    isExpanded: isExpanded,
                    font: .caption2.weight(.semibold),
                    foregroundStyle: JinSemanticColor.textTertiary
                )
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .fill(isHovering ? JinSemanticColor.subtleSurface.opacity(0.7) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
        .accessibilityHint(Text(isExpanded ? "Hides tool details" : "Shows tool details"))
    }
}

// MARK: - Single-tool unified row

/// One control for the common case: icon · tool · status · duration · chevron,
/// optional arg preview, then payload on expand — no nested second header.
struct MCPSingleToolTimelineRow: View {
    let entry: MCPToolTimelineSupport.Entry
    let iconID: String
    let isStreaming: Bool
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var isHovering = false
    /// Payload stays mounted at height 0 while collapsed so the first expand
    /// has a warm height probe (no snap / text flicker).
    @State private var hasMountedPayload = false

    private var parsed: MCPToolTimelineSupport.ParsedFunctionName {
        MCPToolTimelineSupport.parseFunctionName(entry.call.name)
    }

    private var status: ToolCallExecutionStatus { entry.status }

    private var durationText: String? {
        ToolCallViewSupport.durationText(for: entry.result?.durationSeconds)
    }

    private var argumentSummary: String? {
        ToolCallViewSupport.argumentSummary(for: entry.call.arguments)
    }

    private var statusStyle: ToolTimelinePresentationSupport.StatusVisualStyle {
        ToolTimelinePresentationSupport.terminalStatusStyle(for: status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            headerButton

            if let argumentSummary {
                Text(argumentSummary)
                    .font(.caption)
                    .foregroundStyle(JinSemanticColor.textTertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .padding(.leading, 24)
                    .opacity(isExpanded ? 0 : 1)
                    .frame(height: isExpanded ? 0 : nil, alignment: .top)
                    .clipped()
                    .allowsHitTesting(!isExpanded)
                    .accessibilityHidden(isExpanded)
            }

            if hasMountedPayload {
                JinCollapsibleContent(isExpanded: isExpanded) {
                    ToolCallExpandedContentView(
                        formattedArgumentsJSON: ToolCallViewSupport.formattedArgumentsJSON(
                            for: entry.call.arguments
                        ),
                        toolResult: entry.result,
                        signature: entry.call.signature
                    )
                    .padding(.leading, 24)
                    .padding(.top, 2)
                    .padding(.bottom, JinSpacing.xSmall)
                }
            }
        }
        .onAppear {
            if !hasMountedPayload {
                hasMountedPayload = true
            }
        }
    }

    private var headerButton: some View {
        Button(action: onToggle) {
            HStack(spacing: JinSpacing.small) {
                MCPIconView(
                    iconID: iconID,
                    fallbackSystemName: "hammer.fill",
                    size: 13
                )
                .frame(width: 16, height: 16)
                .opacity(0.85)

                Text(parsed.toolName)
                    .font(.system(.subheadline, design: .default).weight(.medium))
                    .foregroundStyle(JinSemanticColor.textSecondary)
                    .lineLimit(1)

                quietStatus

                if isStreaming, status == .running {
                    ProgressView()
                        .controlSize(.mini)
                }

                Spacer(minLength: 0)

                JinDisclosureChevron(
                    isExpanded: isExpanded,
                    font: .caption2.weight(.semibold),
                    foregroundStyle: JinSemanticColor.textTertiary
                )
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .fill(isHovering ? JinSemanticColor.subtleSurface.opacity(0.7) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(accessibilityLabelText))
        .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
        .accessibilityHint(Text(isExpanded ? "Hides tool details" : "Shows tool details"))
    }

    /// Icon + duration only for success; keep a short word for error/running.
    @ViewBuilder
    private var quietStatus: some View {
        HStack(spacing: 4) {
            Image(systemName: statusGlyph)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusStyle.accent)

            if status == .error {
                Text("Failed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusStyle.text)
            } else if status == .running {
                Text("Running")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusStyle.text)
            }

            if let durationText, status != .running {
                Text(durationText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(JinSemanticColor.textTertiary)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    private var statusGlyph: String {
        switch status {
        case .running: return "circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private var accessibilityLabelText: String {
        var parts = [parsed.toolName]
        switch status {
        case .running: parts.append("Running")
        case .success: parts.append("Succeeded")
        case .error: parts.append("Failed")
        }
        if let durationText, status != .running {
            parts.append(durationText)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Icon stack

struct MCPToolTimelineSummaryIconStack: View {
    let serverIDs: [String]
    let iconIDByServerID: [String: String]

    var body: some View {
        if serverIDs.count <= 1 {
            MCPIconView(iconID: summaryIconID, fallbackSystemName: "hammer.fill", size: 13)
                .frame(width: 16, height: 16)
                .opacity(0.85)
        } else {
            let layout = MCPToolTimelineSupport.iconStackLayout(for: serverIDs)

            ZStack(alignment: .leading) {
                ForEach(Array(layout.displayedServerIDs.enumerated()), id: \.element) { index, serverID in
                    MCPIconView(
                        iconID: resolvedIconID(forServerID: serverID),
                        fallbackSystemName: "hammer.fill",
                        size: 13
                    )
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(.regularMaterial)
                            .frame(width: 18, height: 18)
                    )
                    .offset(x: CGFloat(layout.overlapOffset) * CGFloat(index))
                    .zIndex(Double(layout.displayedServerIDs.count - index))
                }
            }
            .frame(width: CGFloat(layout.totalWidth), height: 16)
        }
    }

    private var summaryIconID: String {
        MCPToolTimelineSupport.summaryIconID(
            for: serverIDs,
            iconIDByServerID: iconIDByServerID,
            defaultIconID: MCPIconCatalog.defaultIconID
        )
    }

    private func resolvedIconID(forServerID serverID: String) -> String {
        MCPToolTimelineSupport.resolvedIconID(
            forServerID: serverID,
            iconIDByServerID: iconIDByServerID,
            defaultIconID: MCPIconCatalog.defaultIconID
        )
    }
}

// MARK: - Compact status

private struct MCPToolTimelineCompactStatusView: View {
    let badges: [MCPToolTimelineSupport.CompactStatusBadge]

    var body: some View {
        if !badges.isEmpty {
            HStack(spacing: 5) {
                ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                    HStack(spacing: 2) {
                        Image(systemName: badge.icon)
                            .font(.system(size: 10, weight: .semibold))
                        if badge.count > 1 || badges.count > 1 {
                            Text("\(badge.count)")
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(
                        ToolTimelinePresentationSupport.emphasizedCompactStatusColor(for: badge.tone)
                    )
                }
            }
        }
    }
}

// MARK: - Multi-tool expanded list

struct MCPToolTimelineExpandedPanelView: View {
    let entries: [MCPToolTimelineSupport.Entry]
    let showsPerCallServerTag: Bool
    var onEntryExpansionChanged: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { _, entry in
                ToolCallView(
                    toolCall: entry.call,
                    toolResult: entry.result,
                    showsConnectorAbove: false,
                    showsConnectorBelow: false,
                    showsServerTag: showsPerCallServerTag,
                    chrome: .inline,
                    onExpansionChanged: onEntryExpansionChanged
                )
            }
        }
        .padding(.leading, JinSpacing.medium)
        .padding(.bottom, JinSpacing.xSmall)
    }
}
