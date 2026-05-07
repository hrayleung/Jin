import CoreGraphics
import Foundation

struct TextToSpeechTTSKitSampleBuffer {
    struct AppendResult: Equatable {
        let duration: TimeInterval
        let waveformPeaks: [CGFloat]
    }

    private var pendingSamples: [Float] = []
    private var sampleRate: Int?

    var isEmpty: Bool {
        pendingSamples.isEmpty
    }

    mutating func append(
        _ samples: [Float],
        sampleRate: Int,
        secondsPerPeak: TimeInterval
    ) -> AppendResult? {
        guard !samples.isEmpty, sampleRate > 0 else { return nil }

        self.sampleRate = sampleRate
        pendingSamples.append(contentsOf: samples)

        return AppendResult(
            duration: Double(samples.count) / Double(sampleRate),
            waveformPeaks: AudioWaveformExtractor.rawPeaks(
                from: samples,
                sampleRate: Double(sampleRate),
                secondsPerPeak: secondsPerPeak
            )
        )
    }

    func shouldFlush(
        force: Bool,
        shouldPrimePlayback: Bool,
        initialBatchDuration: TimeInterval,
        clipBatchDuration: TimeInterval
    ) -> Bool {
        guard let sampleRate else { return false }
        return TextToSpeechPlaybackMetricsSupport.shouldFlushTTSKitSamples(
            sampleCount: pendingSamples.count,
            sampleRate: sampleRate,
            force: force,
            shouldPrimePlayback: shouldPrimePlayback,
            initialBatchDuration: initialBatchDuration,
            clipBatchDuration: clipBatchDuration
        )
    }

    mutating func drainQueuedClip() -> TextToSpeechQueuedClip? {
        guard let sampleRate, sampleRate > 0, !pendingSamples.isEmpty else { return nil }

        let clip = TextToSpeechSynthesisExecutor.queuedClip(
            fromFloatSamples: pendingSamples,
            sampleRate: sampleRate
        )
        pendingSamples.removeAll(keepingCapacity: true)
        return clip
    }

    mutating func reset() {
        pendingSamples = []
        sampleRate = nil
    }
}
