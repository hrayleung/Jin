import AVFoundation
import CoreGraphics
import Foundation

struct AudioWaveformAnalysis {
    let rawPeaks: [CGFloat]
    let duration: TimeInterval
}

enum AudioWaveformExtractor {
    static func analyze(data: Data, secondsPerPeak: TimeInterval) -> AudioWaveformAnalysis? {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("audio")

        do {
            try data.write(to: temporaryURL, options: [.atomic])
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            let file = try AVAudioFile(
                forReading: temporaryURL,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            let frameCount = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: frameCount
            ) else {
                return nil
            }

            try file.read(into: buffer)
            guard let channelData = buffer.floatChannelData else { return nil }

            let samples = Array(
                UnsafeBufferPointer(
                    start: channelData[0],
                    count: Int(buffer.frameLength)
                )
            )
            let duration = Double(buffer.frameLength) / file.processingFormat.sampleRate
            return AudioWaveformAnalysis(
                rawPeaks: rawPeaks(
                    from: samples,
                    sampleRate: file.processingFormat.sampleRate,
                    secondsPerPeak: secondsPerPeak
                ),
                duration: duration
            )
        } catch {
            return nil
        }
    }

    static func peaks(
        from samples: [Float],
        sampleRate: Double,
        secondsPerPeak: TimeInterval
    ) -> [CGFloat] {
        normalize(peaks: rawPeaks(from: samples, sampleRate: sampleRate, secondsPerPeak: secondsPerPeak))
    }

    static func rawPeaks(
        from samples: [Float],
        sampleRate: Double,
        secondsPerPeak: TimeInterval
    ) -> [CGFloat] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }

        let samplesPerPeak = max(1, Int(sampleRate * secondsPerPeak))
        let peakCount = (samples.count + samplesPerPeak - 1) / samplesPerPeak
        return (0..<peakCount).map { index in
            let start = index * samplesPerPeak
            let end = min(start + samplesPerPeak, samples.count)
            var peak: Float = 0
            var sumSquares: Float = 0
            for i in start..<end {
                let magnitude = abs(samples[i])
                if magnitude > peak { peak = magnitude }
                sumSquares += samples[i] * samples[i]
            }
            let rms = sqrt(sumSquares / Float(max(1, end - start)))
            return CGFloat(max(rms, peak * 0.22))
        }
    }

    static func normalize(peaks: [CGFloat]) -> [CGFloat] {
        guard !peaks.isEmpty else { return [] }

        let sorted = peaks.sorted()
        let percentileIndex = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
        let referencePeak = sorted[percentileIndex]
        guard referencePeak > 0 else { return Array(repeating: 0, count: peaks.count) }

        let normalized = peaks.map { peak -> CGFloat in
            let scaled = max(0, min(1, peak / referencePeak))
            return CGFloat(pow(Double(scaled), 0.85))
        }
        return smooth(peaks: normalized)
    }

    static func resample(peaks: [CGFloat], targetCount: Int) -> [CGFloat] {
        guard targetCount > 0 else { return [] }
        guard !peaks.isEmpty else { return Array(repeating: 0, count: targetCount) }
        guard peaks.count != targetCount else { return peaks }

        return (0..<targetCount).map { index in
            let start = Int(Double(index) * Double(peaks.count) / Double(targetCount))
            let end = Int(Double(index + 1) * Double(peaks.count) / Double(targetCount))
            let clampedStart = min(start, peaks.count - 1)
            let clampedEnd = max(clampedStart + 1, min(peaks.count, end))
            return peaks[clampedStart..<clampedEnd].max() ?? 0
        }
    }

    private static func smooth(peaks: [CGFloat]) -> [CGFloat] {
        guard peaks.count > 2 else { return peaks }

        return peaks.indices.map { index in
            let previous = peaks[max(0, index - 1)]
            let current = peaks[index]
            let next = peaks[min(peaks.count - 1, index + 1)]
            return previous * 0.2 + current * 0.6 + next * 0.2
        }
    }
}
