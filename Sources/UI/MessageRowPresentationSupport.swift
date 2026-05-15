import CoreGraphics
import Collections
import Foundation

enum MessageRowPresentationSupport {
    static func normalizedAssistantModelLabel(_ label: String?) -> String? {
        label?.trimmedNonEmpty
    }

    static func normalizedMCPServerNames(_ names: [String]) -> [String] {
        var ordered = OrderedSet<String>()

        for name in names {
            guard let label = name.trimmedNonEmpty else { continue }
            ordered.append(label)
        }

        return Array(ordered)
    }

    static func timestampText(
        for timestamp: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let time = timestamp.formatted(date: .omitted, time: .shortened)

        if calendar.isDate(timestamp, inSameDayAs: now) {
            return time
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(timestamp, inSameDayAs: yesterday) {
            return "Yesterday \(time)"
        }

        let day = timestamp.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(day) \(time)"
    }

    struct TextToSpeechPresentation: Equatable {
        let isActive: Bool
        let primarySystemName: String
        let helpText: String
        let stopHelpText: String
        let isPrimaryDisabled: Bool

        init(
            copyText: String,
            isConfigured: Bool,
            isGenerating: Bool,
            isPlaying: Bool,
            isPaused: Bool
        ) {
            isActive = isGenerating || isPlaying || isPaused
            isPrimaryDisabled = copyText.isEmpty || !isConfigured

            primarySystemName = Self.primarySystemName(isPlaying: isPlaying, isPaused: isPaused)
            helpText = Self.helpText(
                isConfigured: isConfigured,
                isGenerating: isGenerating,
                isPlaying: isPlaying,
                isPaused: isPaused
            )
            stopHelpText = Self.stopHelpText(isGenerating: isGenerating)
        }

        private static func primarySystemName(isPlaying: Bool, isPaused: Bool) -> String {
            if isPlaying {
                return "pause.circle"
            }
            if isPaused {
                return "play.circle"
            }
            return "speaker.wave.2"
        }

        private static func helpText(
            isConfigured: Bool,
            isGenerating: Bool,
            isPlaying: Bool,
            isPaused: Bool
        ) -> String {
            if !isConfigured {
                return "Configure Text to Speech in Settings → Plugins → Text to Speech"
            }
            if isGenerating {
                return "Generating speech..."
            }
            if isPlaying {
                return "Pause playback"
            }
            if isPaused {
                return "Resume playback"
            }
            return "Speak"
        }

        private static func stopHelpText(isGenerating: Bool) -> String {
            isGenerating ? "Stop generating speech" : "Stop playback"
        }
    }

    struct UserBlockPartition {
        let imageParts: [RenderedContentPart]
        let remainingBlocks: [RenderedMessageBlock]

        init(blocks: [RenderedMessageBlock]) {
            imageParts = blocks.compactMap(Self.imagePart)
            remainingBlocks = blocks.filter { block in
                Self.imagePart(from: block) == nil
            }
        }

        private static func imagePart(from block: RenderedMessageBlock) -> RenderedContentPart? {
            if case .content(_, let part) = block, case .image = part {
                return part
            }
            return nil
        }
    }

    struct Presentation {
        let isUser: Bool
        let isAssistant: Bool
        let isTool: Bool
        let hidesManagedAgentInternalUI: Bool
        let isEditingUserMessage: Bool
        let assistantModelLabel: String?
        let copyText: String
        let showsCopyButton: Bool
        let canEditUserMessage: Bool
        let canDeleteResponse: Bool
        let effectiveMaxBubbleWidth: CGFloat
        let collapsedPreview: LightweightMessagePreview?
        let visibleToolCalls: [ToolCall]
        let visibleCodeExecutionActivities: [CodeExecutionActivity]
        let visibleRenderedBlocks: [RenderedMessageBlock]
        let hasVisibleAssistantPresentation: Bool
        let rendersRow: Bool

        init(
            item: MessageRenderItem,
            maxBubbleWidth: CGFloat,
            providerType: ProviderType?,
            renderMode: MessageRenderMode,
            editingUserMessageID: UUID?
        ) {
            isUser = item.isUser
            isAssistant = item.isAssistant
            isTool = item.isTool
            hidesManagedAgentInternalUI = ManagedAgentUIVisibilitySupport.hidesInternalUI(providerType: providerType)
            isEditingUserMessage = isUser && editingUserMessageID == item.id
            assistantModelLabel = item.assistantModelLabel
            copyText = item.copyText
            showsCopyButton = (isUser || isAssistant) && !copyText.isEmpty
            canEditUserMessage = item.canEditUserMessage
            canDeleteResponse = item.canDeleteResponse
            effectiveMaxBubbleWidth = Self.effectiveMaxBubbleWidth(
                maxBubbleWidth,
                isUser: isUser
            )
            collapsedPreview = item.collapsedPreviewForDisplay(in: renderMode)
            visibleToolCalls = Self.visibleValues(
                item.visibleToolCalls,
                hidesManagedAgentInternalUI: hidesManagedAgentInternalUI
            )
            visibleCodeExecutionActivities = Self.visibleValues(
                item.codeExecutionActivities,
                hidesManagedAgentInternalUI: hidesManagedAgentInternalUI
            )
            visibleRenderedBlocks = item.renderedBlocks.filter {
                ManagedAgentUIVisibilitySupport.isVisibleRenderedBlock($0, providerType: providerType)
            }

            hasVisibleAssistantPresentation = Self.hasVisibleAssistantPresentation(
                collapsedPreview: collapsedPreview,
                searchActivities: item.searchActivities,
                codeExecutionActivities: visibleCodeExecutionActivities,
                renderedBlocks: visibleRenderedBlocks,
                toolCalls: visibleToolCalls
            )
            rendersRow = !isAssistant || hasVisibleAssistantPresentation
        }

        private static func effectiveMaxBubbleWidth(
            _ maxBubbleWidth: CGFloat,
            isUser: Bool
        ) -> CGFloat {
            guard maxBubbleWidth.isFinite, maxBubbleWidth > 0 else { return 0 }

            if isUser {
                return ChatConversationLayoutMetrics.userBubbleMaxWidth(for: maxBubbleWidth)
            }
            return ChatConversationLayoutMetrics.assistantBubbleMaxWidth(for: maxBubbleWidth)
        }

        private static func visibleValues<Value>(
            _ values: [Value],
            hidesManagedAgentInternalUI: Bool
        ) -> [Value] {
            hidesManagedAgentInternalUI ? [] : values
        }

        private static func hasVisibleAssistantPresentation(
            collapsedPreview: LightweightMessagePreview?,
            searchActivities: [SearchActivity],
            codeExecutionActivities: [CodeExecutionActivity],
            renderedBlocks: [RenderedMessageBlock],
            toolCalls: [ToolCall]
        ) -> Bool {
            collapsedPreview != nil
                || !searchActivities.isEmpty
                || !codeExecutionActivities.isEmpty
                || !renderedBlocks.isEmpty
                || !toolCalls.isEmpty
        }
    }
}
