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
        let showsCopyButton = state.hasVisibleText
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

                        if !state.textChunks.isEmpty {
                            MarkdownWebRenderer(markdownText: state.textContent, isStreaming: true)
                        } else if state.thinkingChunks.isEmpty && state.searchActivities.isEmpty && visibleToolCalls.isEmpty {
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
                            CopyToPasteboardButton(text: state.textContent, helpText: "Copy message", useProminentStyle: false)
                                .accessibilityLabel("Copy message")
                            Spacer(minLength: 0)
                        }
                        .padding(.top, JinSpacing.xSmall - 2)
                    }
                }
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

// MARK: - Streaming Message State

final class StreamingMessageState: ObservableObject {
    private static let maxChunkSize = 2048

    @Published private(set) var textChunks: [String] = []
    @Published private(set) var thinkingChunks: [String] = []
    @Published private(set) var searchActivities: [SearchActivity] = []
    @Published private(set) var streamingToolCalls: [ToolCall] = []
    @Published private(set) var toolResultsByCallID: [String: ToolResult] = [:]
    @Published private(set) var renderTick: Int = 0
    @Published private(set) var hasVisibleText: Bool = false
    @Published private(set) var isThinkingComplete: Bool = false

    private var textStorage = ""
    private var thinkingStorage = ""
    private var searchActivitiesByID: [String: SearchActivity] = [:]
    private var searchActivityOrder: [String] = []

    var textContent: String { textStorage }
    var thinkingContent: String { thinkingStorage }

    func reset() {
        textStorage = ""
        thinkingStorage = ""
        textChunks = []
        thinkingChunks = []
        searchActivities = []
        streamingToolCalls = []
        toolResultsByCallID = [:]
        searchActivitiesByID = [:]
        searchActivityOrder = []
        hasVisibleText = false
        isThinkingComplete = false
        renderTick = 0
    }

    func appendDeltas(textDelta: String, thinkingDelta: String) {
        var didMutate = false

        if !textDelta.isEmpty {
            textStorage.append(textDelta)
            if !hasVisibleText,
               textDelta.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil {
                hasVisibleText = true
            }
            if !isThinkingComplete, !thinkingChunks.isEmpty {
                isThinkingComplete = true
            }
            appendDelta(textDelta, to: &textChunks, maxChunkSize: Self.maxChunkSize)
            didMutate = true
        }

        if !thinkingDelta.isEmpty {
            thinkingStorage.append(thinkingDelta)
            appendDelta(thinkingDelta, to: &thinkingChunks, maxChunkSize: Self.maxChunkSize)
            didMutate = true
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
            searchActivityOrder.append(activity.id)
            searchActivitiesByID[activity.id] = activity
        }
        searchActivities = searchActivityOrder.compactMap { searchActivitiesByID[$0] }
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
