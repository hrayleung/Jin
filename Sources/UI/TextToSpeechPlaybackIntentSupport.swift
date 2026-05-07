import Foundation

enum TextToSpeechPlaybackIntentSupport {
    enum ToggleIntent: Equatable {
        case pauseCurrent
        case resumeCurrent
        case stopCurrent
        case stopCurrentAndIgnoreEmptyInput
        case stopCurrentThenStart(trimmedText: String)
    }

    static func toggleIntent(
        state: TextToSpeechPlaybackManager.State,
        messageID: UUID,
        text: String,
        usesNativeStreamingPlayback: Bool
    ) -> ToggleIntent {
        if let activeIntent = activeMessageToggleIntent(
            state: state,
            messageID: messageID,
            usesNativeStreamingPlayback: usesNativeStreamingPlayback
        ) {
            return activeIntent
        }

        guard let trimmedText = text.trimmedNonEmpty else {
            return .stopCurrentAndIgnoreEmptyInput
        }

        return .stopCurrentThenStart(trimmedText: trimmedText)
    }

    static func isGenerating(_ state: TextToSpeechPlaybackManager.State, messageID: UUID) -> Bool {
        state == .generating(messageID: messageID)
    }

    static func isPlaying(_ state: TextToSpeechPlaybackManager.State, messageID: UUID) -> Bool {
        state == .playing(messageID: messageID)
    }

    static func isPaused(_ state: TextToSpeechPlaybackManager.State, messageID: UUID) -> Bool {
        state == .paused(messageID: messageID)
    }

    static func isActive(_ state: TextToSpeechPlaybackManager.State, messageID: UUID) -> Bool {
        state.activeMessageID == messageID
    }

    private static func activeMessageToggleIntent(
        state: TextToSpeechPlaybackManager.State,
        messageID: UUID,
        usesNativeStreamingPlayback: Bool
    ) -> ToggleIntent? {
        if isPlaying(state, messageID: messageID) {
            return usesNativeStreamingPlayback ? .stopCurrent : .pauseCurrent
        }
        if isPaused(state, messageID: messageID) {
            return .resumeCurrent
        }
        if isGenerating(state, messageID: messageID) {
            return .stopCurrent
        }
        return nil
    }
}
