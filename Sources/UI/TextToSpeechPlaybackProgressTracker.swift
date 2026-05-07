import CoreGraphics
import Foundation

struct TextToSpeechPlaybackProgressTracker {
    private(set) var generatedDuration: TimeInterval = 0
    private(set) var playedDuration: TimeInterval = 0
    private var accumulatedWaveformPeaks: [CGFloat] = []

    mutating func reset() {
        generatedDuration = 0
        playedDuration = 0
        accumulatedWaveformPeaks = []
    }

    mutating func recordGeneratedClip(_ clip: TextToSpeechQueuedClip) -> Bool {
        recordGeneratedAudio(duration: clip.duration, waveformPeaks: clip.waveformPeaks)
    }

    mutating func recordGeneratedAudio(
        duration: TimeInterval,
        waveformPeaks: [CGFloat]
    ) -> Bool {
        generatedDuration += duration
        guard !waveformPeaks.isEmpty else { return false }

        accumulatedWaveformPeaks.append(contentsOf: waveformPeaks)
        return true
    }

    mutating func recordPlayedClip(_ clip: TextToSpeechQueuedClip) {
        playedDuration += clip.duration
    }

    func queuedPlaybackTime(activeClipCurrentTime: TimeInterval?) -> TimeInterval {
        playedDuration + max(0, activeClipCurrentTime ?? 0)
    }

    func publishedMetrics(currentTime: TimeInterval) -> TextToSpeechPlaybackMetricsSupport.PublishedMetrics {
        TextToSpeechPlaybackMetricsSupport.publishedMetrics(
            currentTime: currentTime,
            generatedDuration: generatedDuration
        )
    }

    func displayedWaveformPeaks(targetCount: Int) -> [CGFloat] {
        TextToSpeechPlaybackMetricsSupport.displayedWaveformPeaks(
            accumulatedPeaks: accumulatedWaveformPeaks,
            targetCount: targetCount
        )
    }
}
