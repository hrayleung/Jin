import AVFoundation
import CoreGraphics
import Foundation

enum TextToSpeechQueuedClipFactory {
    static let waveformSecondsPerPeak: TimeInterval = 0.06

    static func clip(fromAudioData data: Data) async -> TextToSpeechQueuedClip {
        let analysis = await Task.detached(priority: .utility) {
            AudioWaveformExtractor.analyze(
                data: data,
                secondsPerPeak: waveformSecondsPerPeak
            )
        }.value

        return TextToSpeechQueuedClip(
            audioData: data,
            duration: analysis?.duration ?? fallbackDuration(for: data),
            waveformPeaks: analysis?.rawPeaks ?? []
        )
    }

    static func clip(fromFloatSamples samples: [Float], sampleRate: Int) -> TextToSpeechQueuedClip {
        TextToSpeechQueuedClip(
            audioData: TextToSpeechWAVContainer.wrapFloat32Mono(samples: samples, sampleRate: sampleRate),
            duration: Double(samples.count) / Double(sampleRate),
            waveformPeaks: []
        )
    }

    private static func fallbackDuration(for data: Data) -> TimeInterval {
        max(0, (try? AVAudioPlayer(data: data).duration) ?? 0)
    }
}
