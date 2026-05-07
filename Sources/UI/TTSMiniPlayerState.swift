import CoreGraphics
import Foundation

@MainActor
final class TTSMiniPlayerState: ObservableObject {
    @Published private(set) var waveformPeaks: [CGFloat]
    @Published private(set) var clipProgress: Double = 0
    @Published private(set) var clipCurrentTime: TimeInterval = 0
    @Published private(set) var clipDuration: TimeInterval = 0

    init(sampleCount: Int) {
        waveformPeaks = Array(repeating: 0, count: sampleCount)
    }

    func reset(sampleCount: Int) {
        waveformPeaks = Array(repeating: 0, count: sampleCount)
        clipProgress = 0
        clipCurrentTime = 0
        clipDuration = 0
    }

    func updateWaveform(_ peaks: [CGFloat]) {
        waveformPeaks = peaks
    }

    func update(metrics: TextToSpeechPlaybackMetricsSupport.PublishedMetrics) {
        if abs(clipCurrentTime - metrics.currentTime) > 0.001 {
            clipCurrentTime = metrics.currentTime
        }
        if abs(clipDuration - metrics.duration) > 0.001 {
            clipDuration = metrics.duration
        }
        if abs(clipProgress - metrics.progress) > 0.0001 {
            clipProgress = metrics.progress
        }
    }
}
