import Collections
import SwiftUI

// MARK: - Streaming Accumulation Types

enum StreamedAssistantPartRef {
    case text(Int)
    case image(Int)
    case video(Int)
    case thinking(Int)
    case redacted(RedactedThinkingBlock)
}

struct ThinkingBlockAccumulator {
    var text: String
    var signature: String?
    var provider: String?
}

// MARK: - Streaming Message View

struct StreamingMessageView: View {
    @ObservedObject var state: StreamingMessageState
    let maxBubbleWidth: CGFloat
    let assistantDisplayName: String
    let modelLabel: String?
    let providerIconID: String?
    let onContentUpdate: () -> Void
    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue

    var body: some View {
        let visibleText = state.visibleText
        let showsCopyButton = !visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let visibleToolCalls = state.streamingToolCalls.filter { call in
            !BuiltinSearchToolHub.isBuiltinSearchFunctionName(call.name)
        }

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

                        if let label = modelLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
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

                        if !state.codexToolActivities.isEmpty {
                            CodexToolTimelineView(
                                activities: state.codexToolActivities,
                                isStreaming: true
                            )
                        }

                        if !state.codeExecutionActivities.isEmpty {
                            CodeExecutionTimelineView(
                                activities: state.codeExecutionActivities,
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

                        if !state.thinkingChunks.isEmpty {
                            StreamingThinkingBlockView(
                                chunks: state.thinkingChunks,
                                codeFont: chatCodeFont,
                                isThinkingComplete: state.isThinkingComplete
                            )
                        }

                        if !visibleText.isEmpty {
                            MarkdownWebRenderer(markdownText: visibleText, isStreaming: true)
                        }

                        if !state.artifacts.isEmpty {
                            ForEach(Array(state.artifacts.enumerated()), id: \.offset) { _, artifact in
                                StreamingArtifactIndicator(artifact: artifact)
                            }
                        } else if state.thinkingChunks.isEmpty && state.searchActivities.isEmpty && state.codexToolActivities.isEmpty && state.codeExecutionActivities.isEmpty && visibleToolCalls.isEmpty {
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
                            CopyToPasteboardButton(text: visibleText, helpText: "Copy message", useProminentStyle: false)
                                .accessibilityLabel("Copy message")
                            Spacer(minLength: 0)
                        }
                        .padding(.top, JinSpacing.xSmall - 2)
                    }
                }
                .layoutValue(key: ConstrainedWidthContentVersionKey.self, value: .version(state.renderTick))
            }
            .padding(.horizontal, JinSpacing.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, JinSpacing.small)
        .onChange(of: state.renderTick) { _, _ in
            onContentUpdate()
        }
    }

    private var chatBodyFont: Font {
        JinTypography.chatBodyFont(appFamilyPreference: appFontFamily, scale: JinTypography.defaultChatMessageScale)
    }

    private var chatCodeFont: Font {
        JinTypography.chatCodeFont(codeFamilyPreference: codeFontFamily, scale: JinTypography.defaultChatMessageScale)
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

// MARK: - Streaming Message State

final class StreamingMessageState: ObservableObject {
    private static let maxChunkSize = 2048

    @Published private(set) var textChunks: [String] = []
    @Published private(set) var thinkingChunks: [String] = []
    @Published private(set) var searchActivities: [SearchActivity] = []
    @Published private(set) var codeExecutionActivities: [CodeExecutionActivity] = []
    @Published private(set) var codexToolActivities: [CodexToolActivity] = []
    @Published private(set) var streamingToolCalls: [ToolCall] = []
    @Published private(set) var toolResultsByCallID: [String: ToolResult] = [:]
    @Published private(set) var renderTick: Int = 0
    @Published private(set) var visibleText: String = ""
    @Published private(set) var artifacts: [ParsedArtifact] = []
    @Published private(set) var hasVisibleText: Bool = false
    @Published private(set) var isThinkingComplete: Bool = false

    private var textStorage = ""
    private var thinkingStorage = ""
    private var searchActivitiesByID: OrderedDictionary<String, SearchActivity> = [:]
    private var codeExecutionActivitiesByID: OrderedDictionary<String, CodeExecutionActivity> = [:]
    private var codexToolActivitiesByID: OrderedDictionary<String, CodexToolActivity> = [:]

    var textContent: String { textStorage }
    var thinkingContent: String { thinkingStorage }

    func reset() {
        textStorage = ""
        thinkingStorage = ""
        textChunks = []
        thinkingChunks = []
        searchActivities = []
        codeExecutionActivities = []
        codexToolActivities = []
        streamingToolCalls = []
        toolResultsByCallID = [:]
        searchActivitiesByID = [:]
        codeExecutionActivitiesByID = [:]
        codexToolActivitiesByID = [:]
        visibleText = ""
        artifacts = []
        hasVisibleText = false
        isThinkingComplete = false
        renderTick = 0
    }

    func appendDeltas(textDelta: String, thinkingDelta: String) {
        var didMutate = false
        var didChangeText = false

        if !textDelta.isEmpty {
            textStorage.append(textDelta)
            if !isThinkingComplete, !thinkingChunks.isEmpty {
                isThinkingComplete = true
            }
            appendDelta(textDelta, to: &textChunks, maxChunkSize: Self.maxChunkSize)
            didChangeText = true
            didMutate = true
        }

        if !thinkingDelta.isEmpty {
            thinkingStorage.append(thinkingDelta)
            appendDelta(thinkingDelta, to: &thinkingChunks, maxChunkSize: Self.maxChunkSize)
            didMutate = true
        }

        if didChangeText {
            updateParsedStreamingContent()
        }

        if didMutate {
            renderTick &+= 1
        }
    }

    func appendTextDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        appendDeltas(textDelta: delta, thinkingDelta: "")
    }

    func appendThinkingDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        appendDeltas(textDelta: "", thinkingDelta: delta)
    }

    func markThinkingComplete() {
        guard !isThinkingComplete, !thinkingChunks.isEmpty else { return }
        isThinkingComplete = true
        renderTick &+= 1
    }

    func upsertSearchActivity(_ activity: SearchActivity) {
        if let existing = searchActivitiesByID[activity.id] {
            searchActivitiesByID[activity.id] = existing.merged(with: activity)
        } else {
            searchActivitiesByID[activity.id] = activity
        }
        searchActivities = Array(searchActivitiesByID.values)
        renderTick &+= 1
    }

    func upsertCodeExecutionActivity(_ activity: CodeExecutionActivity) {
        if let existing = codeExecutionActivitiesByID[activity.id] {
            codeExecutionActivitiesByID[activity.id] = existing.merged(with: activity)
        } else {
            codeExecutionActivitiesByID[activity.id] = activity
        }
        codeExecutionActivities = Array(codeExecutionActivitiesByID.values)
        renderTick &+= 1
    }

    func upsertCodexToolActivity(_ activity: CodexToolActivity) {
        if let existing = codexToolActivitiesByID[activity.id] {
            codexToolActivitiesByID[activity.id] = existing.merged(with: activity)
        } else {
            codexToolActivitiesByID[activity.id] = activity
        }
        codexToolActivities = Array(codexToolActivitiesByID.values)
        renderTick &+= 1
    }

    func setToolCalls(_ toolCalls: [ToolCall]) {
        streamingToolCalls = toolCalls
        toolResultsByCallID = [:]
        renderTick &+= 1
    }

    func upsertToolResult(_ result: ToolResult) {
        guard streamingToolCalls.contains(where: { $0.id == result.toolCallID }) else { return }
        toolResultsByCallID[result.toolCallID] = result
        renderTick &+= 1
    }

    private func updateParsedStreamingContent() {
        let parseResult = ArtifactMarkupParser.parse(textStorage, hidesTrailingIncompleteArtifact: true)
        visibleText = parseResult.visibleText
        artifacts = parseResult.artifacts
        hasVisibleText = !visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func appendDelta(_ delta: String, to chunks: inout [String], maxChunkSize: Int) {
        if chunks.isEmpty {
            chunks.append(delta)
        } else {
            chunks[chunks.count - 1].append(delta)
        }

        while let lastChunk = chunks.last, lastChunk.count > maxChunkSize {
            let maxIndex = lastChunk.index(lastChunk.startIndex, offsetBy: maxChunkSize)
            let candidate = lastChunk[..<maxIndex]

            let splitIndex = candidate.lastIndex(of: "\n").map { lastChunk.index(after: $0) } ?? maxIndex
            let prefix = String(lastChunk[..<splitIndex])
            let suffix = String(lastChunk[splitIndex...])

            chunks[chunks.count - 1] = prefix
            if !suffix.isEmpty {
                chunks.append(suffix)
            }
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
