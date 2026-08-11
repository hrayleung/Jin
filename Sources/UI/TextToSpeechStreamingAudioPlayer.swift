import AVFoundation
import CoreGraphics
import Foundation

/// Gapless playback for the streaming text-to-speech paths.
///
/// `AVAudioPlayer` cannot join clips without an audible seam. That is invisible today because a
/// whole message is usually one request, but streaming delivers sub-second chunks — at that
/// granularity the seams become a continuous stutter. `AVAudioPlayerNode.scheduleBuffer`
/// queues PCM buffers back to back inside one render graph, so there is no seam at all.
@MainActor
final class TextToSpeechStreamingAudioPlayer {
    /// What a freshly appended chunk contributed, for the shared progress tracker.
    struct AppendedAudio {
        let duration: TimeInterval
        let waveformPeaks: [CGFloat]
    }

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var format: AVAudioFormat?
    private var sampleRate: Double = 24_000
    private var secondsPerPeak: TimeInterval = TextToSpeechQueuedClipFactory.waveformSecondsPerPeak

    /// A chunk boundary can split a 16-bit frame in half.
    private var pendingByte: UInt8?
    /// Samples left over from the last incomplete waveform bucket.
    private var pendingPeakSamples: [Float] = []

    private var scheduledBufferCount = 0
    private var completedBufferCount = 0
    private var didStartPlayback = false
    private var didFinishProducing = false
    private var isStopped = false
    private var lastKnownTime: TimeInterval = 0
    private var onPlaybackFinished: (() -> Void)?

    var hasStartedPlayback: Bool { didStartPlayback }

    /// Seconds of audio played so far. Frozen while paused, which is exactly what the
    /// progress tracker wants.
    var currentTime: TimeInterval {
        guard didStartPlayback,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else {
            return lastKnownTime
        }

        lastKnownTime = max(0, Double(playerTime.sampleTime) / playerTime.sampleRate)
        return lastKnownTime
    }

    func start(
        sampleRate: Double,
        secondsPerPeak: TimeInterval = TextToSpeechQueuedClipFactory.waveformSecondsPerPeak,
        onPlaybackFinished: @escaping () -> Void
    ) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw LLMError.providerError(
                code: "audio_format_error",
                message: "Could not prepare a \(Int(sampleRate)) Hz audio format."
            )
        }

        self.sampleRate = sampleRate
        self.secondsPerPeak = secondsPerPeak
        self.format = format
        self.onPlaybackFinished = onPlaybackFinished

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
    }

    /// Converts a raw 16-bit little-endian mono PCM chunk into a scheduled buffer.
    @discardableResult
    func append(pcm16 data: Data) -> AppendedAudio? {
        guard !isStopped, let format else { return nil }

        let samples = float32Samples(from: data)
        guard !samples.isEmpty else { return nil }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let channelData = buffer.floatChannelData else {
            return nil
        }

        samples.withUnsafeBufferPointer { source in
            channelData[0].update(from: source.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        scheduledBufferCount += 1
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleBufferPlayedBack()
            }
        }

        // Only start the transport once there is something to render, otherwise the node's
        // sample clock would run ahead of the audio during the first request round trip.
        if !didStartPlayback {
            didStartPlayback = true
            playerNode.play()
        }

        return AppendedAudio(
            duration: Double(samples.count) / sampleRate,
            waveformPeaks: waveformPeaks(appending: samples)
        )
    }

    /// Signals that no further chunks will arrive, so draining the scheduled buffers ends the session.
    func finishProducing() {
        didFinishProducing = true
        finishIfDrained()
    }

    func pause() {
        guard didStartPlayback, !isStopped else { return }
        _ = currentTime
        playerNode.pause()
    }

    func resume() {
        guard didStartPlayback, !isStopped else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        playerNode.play()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        onPlaybackFinished = nil

        playerNode.stop()
        engine.stop()
        engine.disconnectNodeOutput(playerNode)
        engine.detach(playerNode)

        pendingByte = nil
        pendingPeakSamples = []
        lastKnownTime = 0
    }

    private func handleBufferPlayedBack() {
        guard !isStopped else { return }
        completedBufferCount += 1
        finishIfDrained()
    }

    private func finishIfDrained() {
        guard !isStopped,
              didFinishProducing,
              completedBufferCount >= scheduledBufferCount else {
            return
        }

        let handler = onPlaybackFinished
        onPlaybackFinished = nil
        handler?()
    }

    private func float32Samples(from data: Data) -> [Float] {
        var bytes = Data()
        if let pendingByte {
            bytes.append(pendingByte)
            self.pendingByte = nil
        }
        bytes.append(data)

        if bytes.count % 2 == 1 {
            pendingByte = bytes.last
            bytes.removeLast()
        }

        guard !bytes.isEmpty else { return [] }

        let scale = Float(Int16.max)
        return bytes.withUnsafeBytes { raw -> [Float] in
            let count = raw.count / 2
            return (0..<count).map { index in
                let low = UInt16(raw[index * 2])
                let high = UInt16(raw[index * 2 + 1])
                let value = Int16(bitPattern: low | (high << 8))
                return Float(value) / scale
            }
        }
    }

    /// Carries incomplete buckets across chunk boundaries so the waveform stays evenly spaced.
    private func waveformPeaks(appending samples: [Float]) -> [CGFloat] {
        pendingPeakSamples.append(contentsOf: samples)

        let samplesPerPeak = max(1, Int(sampleRate * secondsPerPeak))
        let completeBucketCount = pendingPeakSamples.count / samplesPerPeak
        guard completeBucketCount > 0 else { return [] }

        let consumedCount = completeBucketCount * samplesPerPeak
        let bucketed = Array(pendingPeakSamples[0..<consumedCount])
        pendingPeakSamples.removeFirst(consumedCount)

        return AudioWaveformExtractor.rawPeaks(
            from: bucketed,
            sampleRate: sampleRate,
            secondsPerPeak: secondsPerPeak
        )
    }
}
