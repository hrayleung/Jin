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
    /// When the last persisted assistant already owns in-flight MCP tools,
    /// collapse this row instead of painting a second empty bubble.
    var suppressIdlePlaceholder: Bool = false
    /// Live results + suppress flag. Observed so the empty Generating row
    /// can collapse without a table `rootView` remount.
    @ObservedObject var liveToolResults: ChatLiveToolResultStore
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue
    /// Bumped when row-internal state changes the content's height outside
    /// of a streaming delta (thinking block expand/collapse). Folded into
    /// `streamingLayoutVersion` so the cached measurement is invalidated.
    @State private var layoutEpoch = 0

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
        let showsIdlePlaceholder = showsIdleGeneratingPlaceholder(
            visibleThinkingChunks: visibleThinkingChunks,
            visibleCodeExecutionActivities: visibleCodeExecutionActivities,
            visibleToolCalls: visibleToolCalls
        )

        Group {
        if showsIdlePlaceholder, effectiveSuppressIdlePlaceholder {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 0)
                .accessibilityHidden(true)
        } else {
        HStack(alignment: .top, spacing: 0) {
            ConstrainedWidth(maxBubbleWidth) {
                VStack(alignment: .leading, spacing: JinSpacing.small - 2) {
                    VStack(alignment: .leading, spacing: JinSpacing.small) {
                        HStack(spacing: JinSpacing.small - 2) {
                            ProviderBadgeIcon(iconID: providerIconID)

                            Text(ChatConversationMinimapGeometry.assistantRoleLabel(displayName: assistantDisplayName))
                                .jinSectionHeader()
                                .foregroundStyle(JinSemanticColor.textTertiary)

                            if let label = modelLabel?.trimmedNonEmpty {
                                Text(label)
                                    .jinTagStyle()
                            }

                            streamingHeaderActivity

                            // No greedy Spacer: on macOS 27's ConstrainedWidth
                            // (frame+fixedSize) a Spacer can inflate the bubble
                            // to a tall empty gray plate while the real chrome
                            // fails to paint. The header is already leading-
                            // aligned inside a full-width column.
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if !state.searchActivities.isEmpty {
                            SearchActivityTimelineView(
                                activities: state.searchActivities,
                                isStreaming: true,
                                providerLabel: ChatConversationMinimapGeometry.customAssistantDisplayName(assistantDisplayName),
                                modelLabel: modelLabel,
                                onExpansionChanged: { layoutEpoch &+= 1 }
                            )
                        }

                        if !visibleCodeExecutionActivities.isEmpty {
                            CodeExecutionTimelineView(
                                activities: visibleCodeExecutionActivities,
                                isStreaming: true,
                                onExpansionChanged: { layoutEpoch &+= 1 }
                            )
                        }

                        if !visibleThinkingChunks.isEmpty {
                            StreamingThinkingBlockView(
                                chunks: visibleThinkingChunks,
                                codeFont: chatCodeFont,
                                isThinkingComplete: state.isThinkingComplete,
                                onExpansionChanged: { layoutEpoch &+= 1 }
                            )
                        }

                        // Prefer real tokens when the model has produced
                        // non-whitespace text. Whitespace-only prefixes used to
                        // hide the Generating placeholder and paint an empty
                        // markdown tree — the "blank bubble while busy" glitch.
                        if state.hasVisibleText {
                            // No cross-fade on token growth — animating the
                            // markdown tree re-introduces stacked glyphs.
                            streamingTextView(visibleText)
                                .transition(.identity)
                        }

                        if !state.artifacts.isEmpty {
                            ForEach(Array(state.artifacts.enumerated()), id: \.offset) { _, artifact in
                                StreamingArtifactIndicator(artifact: artifact)
                            }
                        } else if showsIdlePlaceholder {
                            // Elegant time-based idle chrome — never a system spinner.
                            // Identity transition: opacity cross-fade with the first
                            // token layer caused a one-frame glyph stack.
                            JinStreamingPlaceholder(label: "Generating")
                                .transition(.identity)
                        }

                        // After prose, matching MessageRow. Painting MCP cards
                        // above the text here made search/fetch jump under the
                        // paragraph the moment the turn persisted.
                        if !visibleToolCalls.isEmpty {
                            MCPToolTimelineView(
                                toolCalls: visibleToolCalls,
                                toolResultsByCallID: state.toolResultsByCallID,
                                isStreaming: true,
                                onExpansionChanged: { layoutEpoch &+= 1 }
                            )
                        }
                    }
                    .padding(JinSpacing.medium)
                    .jinSurface(.subtle, cornerRadius: JinRadius.large)

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
                .layoutValue(key: ConstrainedWidthContentVersionKey.self, value: .version(streamingLayoutVersion))
            }
            .padding(.horizontal, JinSpacing.small)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, JinSpacing.small)
        // Streaming flushes must never inherit an ambient animation — that
        // interpolated layouts between successive markdown trees and briefly
        // stacked two font layers ("overlapping glyphs while generating").
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        }
        }
        .onChange(of: streamingLayoutVersion) { _, _ in
            onContentUpdate()
        }
    }

    /// ConstrainedWidth + row-height pulse. Every coalesced presentation flush
    /// can change wrapping (including a newline or short CJK line), so it must
    /// invalidate the measured height. The orb now runs in Core Animation and
    /// is unaffected by these SwiftUI layout passes.
    private var streamingLayoutVersion: Int {
        var version = state.renderTick &* 31
        version &+= layoutEpoch
        version &+= effectiveSuppressIdlePlaceholder ? 1 : 0
        return version
    }

    private var effectiveSuppressIdlePlaceholder: Bool {
        suppressIdlePlaceholder || liveToolResults.suppressIdleStreamingPlaceholder
    }

    /// One live orb for the whole streaming turn. Kind updates in place so
    /// thinking / search / tools never remount a representable mid-hitch.
    private var streamingHeaderActivity: some View {
        let hidesManagedAgentInternalUI = ManagedAgentUIVisibilitySupport.hidesInternalUI(
            providerType: providerType
        )
        let kind = JinActivityKind.resolveStreaming(
            searchActivities: state.searchActivities,
            codeExecutionActivities: hidesManagedAgentInternalUI ? [] : state.codeExecutionActivities,
            toolCalls: hidesManagedAgentInternalUI ? [] : state.streamingToolCalls.filter { call in
                !BuiltinSearchToolHub.isBuiltinSearchFunctionName(call.name)
                && !isGoogleProviderNativeToolName(call.name)
            },
            toolResultsByCallID: state.toolResultsByCallID,
            artifactCount: state.artifacts.count,
            hasVisibleText: state.hasVisibleText,
            thinkingChunkCount: hidesManagedAgentInternalUI ? 0 : state.thinkingChunks.count,
            isThinkingComplete: state.isThinkingComplete
        )
        return HStack(spacing: 4) {
            JinActivityOrb(kind: kind, size: .inline)
            Text(kind.statusLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(JinSemanticColor.textTertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(kind.accessibilityLabel))
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

    /// True only while the model has produced nothing visible yet — no
    /// thinking, tools, search, code-exec, artifacts, or non-whitespace text.
    private func showsIdleGeneratingPlaceholder(
        visibleThinkingChunks: [String],
        visibleCodeExecutionActivities: [CodeExecutionActivity],
        visibleToolCalls: [ToolCall]
    ) -> Bool {
        visibleThinkingChunks.isEmpty
            && state.searchActivities.isEmpty
            && visibleCodeExecutionActivities.isEmpty
            && visibleToolCalls.isEmpty
            && !state.hasVisibleText
            && state.artifacts.isEmpty
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

    /// `body` runs several times per flush (renderTick plus layout probes),
    /// and building the attributed string is O(accumulated text): join, UTF-16
    /// conversion, CJK bracket scan. Memoize the built string on a cheap
    /// signature so construction happens once per content change instead of
    /// once per body evaluation. A reference-type box mutated during `body` is
    /// deliberate — it must not re-invalidate the view.
    @State private var memo = Memo()

    private final class Memo {
        var byteCount = -1
        var tailFingerprint: UInt64 = 0
        var fontKey = ""
        var attributedString = NSAttributedString()
    }

    var body: some View {
        let theme = MarkdownTheme.resolved(appFontFamily: appFontFamily, codeFontFamily: codeFontFamily)
        let byteCount = chunks.reduce(0) { $0 + $1.utf8.count }
        // Byte count alone could collide across recycled view identities
        // (different message, equal length); hashing the bounded last chunk
        // (≤ maxChunkSize) closes that without an O(n) pass.
        var tailHasher = FNVHasher()
        tailHasher.combine(chunks.last ?? "")
        let tailFingerprint = tailHasher.value
        let fontKey = "\(appFontFamily)|\(codeFontFamily)"

        if memo.byteCount != byteCount || memo.tailFingerprint != tailFingerprint || memo.fontKey != fontKey {
            memo.attributedString = CJKPunctuationSpacing.applied(to: NSAttributedString(
                string: chunks.joined(),
                attributes: [
                    .font: theme.bodyFont,
                    .foregroundColor: theme.baseColor,
                    // Match the post-stream rich render's body line metrics
                    // (lineHeightMultiple etc.) so the swap at stream end
                    // doesn't reflow every line of a >4000-char message.
                    .paragraphStyle: theme.bodyParagraphStyle,
                ]
            ))
            memo.byteCount = byteCount
            memo.tailFingerprint = tailFingerprint
            memo.fontKey = fontKey
        }

        // Mix the tail fingerprint into the signature the TextKit applier
        // compares: a bare byte count would let a recycled cell skip applying
        // different-but-equal-length content.
        return AttributedTextBlock(
            attributedString: memo.attributedString,
            contentSignature: UInt64(byteCount) &+ tailFingerprint
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Streaming Artifact Indicator

private struct StreamingArtifactIndicator: View {
    let artifact: ParsedArtifact

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(accentColor.opacity(0.12))
                .frame(width: 24, height: 24)
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

            ArtifactTypeBadge(contentType: artifact.contentType)
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
