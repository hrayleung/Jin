import CoreGraphics
import Foundation

struct TTSMiniPlayerSnapshot: Equatable {
    let title: String
    let timeText: String
    let waveformPeaks: [CGFloat]
    let progress: Double
    let isGenerating: Bool
    let isPlaying: Bool
    let isPaused: Bool
    let showsPrimarySpinner: Bool
    let showsWaveform: Bool
    let showsWaveformSpinner: Bool
    let canNavigate: Bool
    let navigateToolTip: String?
}

enum TTSMiniPlayerSnapshotSupport {
    static func snapshot(
        state: TextToSpeechPlaybackManager.State,
        playbackContext: TextToSpeechPlaybackManager.PlaybackContext?,
        waveformPeaks: [CGFloat],
        progress: Double,
        currentTime: TimeInterval,
        hasNavigateHandler: Bool
    ) -> TTSMiniPlayerSnapshot {
        let flags = stateFlags(for: state)
        let title = playbackContext?.conversationTitle ?? "Text to Speech"
        let hasWaveform = waveformPeaks.contains { $0 > 0.001 }

        return TTSMiniPlayerSnapshot(
            title: title,
            timeText: formattedTime(currentTime),
            waveformPeaks: waveformPeaks,
            progress: progress,
            isGenerating: flags.isGenerating,
            isPlaying: flags.isPlaying,
            isPaused: flags.isPaused,
            showsPrimarySpinner: flags.isGenerating,
            showsWaveform: hasWaveform,
            showsWaveformSpinner: flags.isGenerating && !hasWaveform,
            canNavigate: playbackContext != nil && hasNavigateHandler,
            navigateToolTip: playbackContext.map { "Jump to \($0.conversationTitle)" }
        )
    }

    static func activeMessageID(for state: TextToSpeechPlaybackManager.State) -> UUID? {
        state.activeMessageID
    }

    static func formattedTime(_ seconds: TimeInterval) -> String {
        let clamped = max(0, Int(seconds.rounded(.down)))
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }

        return String(format: "%02d:%02d", minutes, secs)
    }

    private static func stateFlags(
        for state: TextToSpeechPlaybackManager.State
    ) -> (isGenerating: Bool, isPlaying: Bool, isPaused: Bool) {
        switch state {
        case .generating:
            return (true, false, false)
        case .playing:
            return (false, true, false)
        case .paused:
            return (false, false, true)
        case .idle:
            return (false, false, false)
        }
    }
}
