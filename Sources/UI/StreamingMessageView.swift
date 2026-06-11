import SwiftUI

struct StreamingMessageView: View {
    private static let richMarkdownCharacterLimit = 4_000

    @ObservedObject var state: StreamingMessageState
    let maxBubbleWidth: CGFloat
    let assistantDisplayName: String
    let modelLabel: String?
    let modelID: String?
    let providerType: ProviderType?
    let providerIconID: String?
    let onContentUpdate: () -> Void
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue

    var body: some View {
        let hidesManagedAgentInternalUI = ManagedAgentUIVisibilitySupport.hidesInternalUI(providerType: providerType)
        let visibleText = state.visibleText
        let showsCopyButton = state.hasVisibleText
        let visibleToolCalls = hidesManagedAgentInternalUI ? [] : state.streamingToolCalls.filter { call in
            !BuiltinSearchToolHub.isBuiltinSearchFunctionName(call.name)
            && !isGoogleProviderNativeToolName(call.name)
        }
        let visibleCodeExecutionActivities = hidesManagedAgentInternalUI ? [] : state.codeExecutionActivities
        let visibleThinkingChunks = hidesManagedAgentInternalUI ? [] : state.thinkingChunks

        HStack(alignment: .top, spacing: 0) {
            ConstrainedWidth(maxBubbleWidth) {
                VStack(alignment: .leading, spacing: JinSpacing.small - 2) {
                    HStack(spacing: JinSpacing.small - 2) {
                        ProviderBadgeIcon(iconID: providerIconID)

                        if assistantDisplayName != "Assistant" {
                            Text(assistantDisplayName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }

                        if let label = modelLabel?.trimmedNonEmpty {
                            Text(label)
                                .jinTagStyle()
                        }
                    }
                    .padding(.horizontal, JinSpacing.medium)
                    .padding(.bottom, 2)

                    VStack(alignment: .leading, spacing: JinSpacing.small) {
                        if !state.searchActivities.isEmpty {
                            SearchActivityTimelineView(
                                activities: state.searchActivities,
                                isStreaming: true,
                                providerLabel: assistantDisplayName == "Assistant" ? nil : assistantDisplayName,
                                modelLabel: modelLabel
                            )
                        }

                        if !visibleCodeExecutionActivities.isEmpty {
                            CodeExecutionTimelineView(
                                activities: visibleCodeExecutionActivities,
                                isStreaming: true
                            )
                        }

                        if !visibleToolCalls.isEmpty {
                            MCPToolTimelineView(
                                toolCalls: visibleToolCalls,
                                toolResultsByCallID: state.toolResultsByCallID,
                                isStreaming: true
                            )
                        }

                        if !visibleThinkingChunks.isEmpty {
                            StreamingThinkingBlockView(
                                chunks: visibleThinkingChunks,
                                codeFont: chatCodeFont,
                                isThinkingComplete: state.isThinkingComplete
                            )
                        }

                        if !visibleText.isEmpty {
                            streamingTextView(visibleText)
                        }

                        if !state.artifacts.isEmpty {
                            ForEach(Array(state.artifacts.enumerated()), id: \.offset) { _, artifact in
                                StreamingArtifactIndicator(artifact: artifact)
                            }
                        } else if visibleThinkingChunks.isEmpty
                                    && state.searchActivities.isEmpty
                                    && visibleCodeExecutionActivities.isEmpty
                                    && visibleToolCalls.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.5)
                                Text("Generating...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(JinSpacing.medium)
                    .jinSurface(.neutral, cornerRadius: JinRadius.medium)

                    if showsCopyButton {
                        HStack {
                            CopyToPasteboardButton(
                                text: visibleText,
                                helpText: "Copy message",
                                useProminentStyle: false,
                                isDisabled: !state.hasVisibleText
                            )
                                .accessibilityLabel("Copy message")
                            Spacer(minLength: 0)
                        }
                        .padding(.top, JinSpacing.xSmall - 2)
                    }
                }
                .layoutValue(key: ConstrainedWidthContentVersionKey.self, value: .version(state.renderTick))
            }
            .padding(.horizontal, JinSpacing.small)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, JinSpacing.small)
        .onChange(of: state.renderTick) { _, _ in
            onContentUpdate()
        }
    }

    @ViewBuilder
    private func streamingTextView(_ visibleText: String) -> some View {
        if state.visibleTextCharacterCount <= Self.richMarkdownCharacterLimit {
            NativeMarkdownView(
                markdownText: visibleText,
                isStreaming: true
            )
        } else {
            StreamingPlainTextChunksView(chunks: state.visibleTextChunks)
        }
    }

    private var chatCodeFont: Font {
        JinTypography.chatCodeFont(codeFamilyPreference: codeFontFamily, scale: JinTypography.defaultChatMessageScale)
    }
}

/// Plain-text fallback shown while a *long* (> `richMarkdownCharacterLimit`)
/// message is still streaming. The earlier implementation composed a SwiftUI
/// `Text` tree with `.textSelection(.enabled)`; that re-shaped the entire
/// growing string on every layout probe (and the streaming bubble is probed
/// repeatedly per flush by `ConstrainedWidth` + `NSHostingView`'s intrinsic
/// sizing), which was the dominant on-main cost of the streaming lag.
///
/// Routing the text through `AttributedTextBlock` instead reuses the
/// renderer's `JinMessageTextView`, whose height is memoized by
/// `(textStorage length, width)` so repeated same-width probes in one layout
/// pass are free, whose layer-backing keeps scroll compositing cheap, and
/// which is selectable out of the box. The `contentSignature` (the text's
/// byte length — monotonic while streaming) gates `setAttributedString` to
/// once per flush. Attributes mirror the canonical plain-text path in
/// `NativeMarkdownCache.compute`, so the swap to the fully-rendered message
/// at stream end stays visually consistent.
private struct StreamingPlainTextChunksView: View {
    let chunks: [String]

    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue

    var body: some View {
        let theme = MarkdownTheme.resolved(appFontFamily: appFontFamily, codeFontFamily: codeFontFamily)
        let text = chunks.joined()
        AttributedTextBlock(
            attributedString: NSAttributedString(
                string: text,
                attributes: [
                    .font: theme.bodyFont,
                    .foregroundColor: theme.baseColor,
                    // Match the post-stream rich render's body line metrics
                    // (lineHeightMultiple etc.) so the swap at stream end
                    // doesn't reflow every line of a >4000-char message.
                    .paragraphStyle: theme.bodyParagraphStyle,
                ]
            ),
            contentSignature: UInt64(text.utf8.count)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Streaming Artifact Indicator

private struct StreamingArtifactIndicator: View {
    let artifact: ParsedArtifact

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(accentColor.opacity(0.12))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

            Text(artifact.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
                ArtifactTypeBadge(contentType: artifact.contentType)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .fill(JinSemanticColor.subtleSurface.opacity(0.7))
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: JinRadius.small,
                bottomLeadingRadius: JinRadius.small,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(accentColor)
            .frame(width: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .stroke(accentColor.opacity(0.12), lineWidth: JinStrokeWidth.hairline)
        )
    }

    private var accentColor: Color {
        switch artifact.contentType {
        case .react:
            return Color(red: 0.55, green: 0.68, blue: 0.78)
        case .html:
            return Color(red: 0.75, green: 0.58, blue: 0.50)
        case .echarts:
            return Color(red: 0.55, green: 0.70, blue: 0.60)
        }
    }

    private var iconName: String {
        switch artifact.contentType {
        case .react:
            return "atom"
        case .html:
            return "globe"
        case .echarts:
            return "chart.bar.xaxis"
        }
    }
}

// MARK: - Preference Keys

struct ComposerHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct BottomSentinelMaxYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
