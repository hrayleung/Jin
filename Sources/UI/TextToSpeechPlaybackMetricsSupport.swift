import CoreGraphics
import Foundation

enum TextToSpeechPlaybackMetricsSupport {
    struct PublishedMetrics: Equatable {
        let currentTime: TimeInterval
        let duration: TimeInterval
        let progress: Double
    }

    static func publishedMetrics(
        currentTime: TimeInterval,
        generatedDuration: TimeInterval
    ) -> PublishedMetrics {
        let clampedCurrent = max(0, currentTime)
        let duration = max(generatedDuration, clampedCurrent)
        let progress = duration > 0 ? min(1, clampedCurrent / duration) : 0

        return PublishedMetrics(
            currentTime: clampedCurrent,
            duration: duration,
            progress: progress
        )
    }

    static func displayedWaveformPeaks(
        accumulatedPeaks: [CGFloat],
        targetCount: Int
    ) -> [CGFloat] {
        AudioWaveformExtractor.normalize(
            peaks: AudioWaveformExtractor.resample(
                peaks: accumulatedPeaks,
                targetCount: targetCount
            )
        )
    }
}
