import Collections
import Foundation
import AVFoundation
import CoreGraphics

@MainActor
final class TextToSpeechPlaybackManager: NSObject, ObservableObject {
    static let waveformDisplaySampleCount = 56
    private static let playbackRefreshInterval: TimeInterval = 1.0 / 15.0
    private static let ttsKitInitialBatchDuration: TimeInterval = 0.12
    private static let ttsKitClipBatchDuration: TimeInterval = 0.9

    @Published private(set) var state: State = .idle
    @Published private(set) var playbackContext: PlaybackContext?
    let miniPlayerState = TTSMiniPlayerState(sampleCount: 56)

    private var synthesisTask: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var queue: Deque<TextToSpeechQueuedClip> = []
    private var activeClip: TextToSpeechQueuedClip?
    private var currentMessageID: UUID?
    private var currentErrorHandler: ((Error) -> Void)?
    private var didFinishSynthesis = true
    private var currentPlaybackBackend: TextToSpeechPlaybackBackend?
    private var meteringTimer: Timer?
    private var progressTracker = TextToSpeechPlaybackProgressTracker()
    private var ttsKitSampleBuffer = TextToSpeechTTSKitSampleBuffer()

    func toggleSpeak(
        messageID: UUID,
        text: String,
        config: SynthesisConfig,
        context: PlaybackContext,
        onError: @escaping (Error) -> Void
    ) {
        switch TextToSpeechPlaybackIntentSupport.toggleIntent(
            state: state,
            messageID: messageID,
            text: text,
            usesNativeStreamingPlayback: currentPlaybackBackend == .nativeTTSKit
        ) {
        case .pauseCurrent:
            pause(messageID: messageID)
        case .resumeCurrent:
            resume(messageID: messageID)
        case .stopCurrent:
            stop(messageID: messageID)
        case .stopCurrentAndIgnoreEmptyInput:
            stop()
        case .stopCurrentThenStart(let trimmedText):
            stop()
            startSynthesis(
                messageID: messageID,
                text: trimmedText,
                config: config,
                context: context,
                onError: onError
            )
        }
    }

    private func startSynthesis(
        messageID: UUID,
        text: String,
        config: SynthesisConfig,
        context: PlaybackContext,
        onError: @escaping (Error) -> Void
    ) {
        didFinishSynthesis = false
        currentMessageID = messageID
        currentErrorHandler = onError
        playbackContext = context
        currentPlaybackBackend = config.usesNativeStreamingPlayback ? .nativeTTSKit : .queuedClips
        state = .generating(messageID: messageID)

        synthesisTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.synthesizeAndEnqueueAudioClips(text: text, config: config, messageID: messageID)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.completeSynthesisIfCurrent(messageID: messageID)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.failSynthesisIfCurrent(messageID: messageID, error: error)
                }
            }
        }
    }

    func isGenerating(messageID: UUID) -> Bool {
        TextToSpeechPlaybackIntentSupport.isGenerating(state, messageID: messageID)
    }

    func isPlaying(messageID: UUID) -> Bool {
        TextToSpeechPlaybackIntentSupport.isPlaying(state, messageID: messageID)
    }

    func isPaused(messageID: UUID) -> Bool {
        TextToSpeechPlaybackIntentSupport.isPaused(state, messageID: messageID)
    }

    func isActive(messageID: UUID) -> Bool {
        TextToSpeechPlaybackIntentSupport.isActive(state, messageID: messageID)
    }

    func pause(messageID: UUID) {
        guard case .playing(let id) = state, id == messageID else { return }

        if let player, player.isPlaying {
            player.pause()
            updateQueuedPlaybackMetrics()
        }

        stopMeteringTimer()
        state = .paused(messageID: messageID)
    }

    func resume(messageID: UUID) {
        guard case .paused(let id) = state, id == messageID else { return }

        state = .playing(messageID: messageID)

        if let player, !player.isPlaying {
            player.play()
            startMeteringTimer()
        }

        playNextClipIfNeeded()
    }

    func stop(messageID: UUID) {
        guard isActive(messageID: messageID) else { return }
        stop()
    }

    func stop() {
        let playbackBackend = currentPlaybackBackend
        synthesisTask?.cancel()
        synthesisTask = nil

        if playbackBackend == .nativeTTSKit {
            Task {
                await TTSKitService.shared.stopPlayback()
            }
        }

        stopMeteringTimer()
        player?.stop()
        player = nil
        queue = []
        activeClip = nil
        currentMessageID = nil
        currentErrorHandler = nil
        didFinishSynthesis = true
        playbackContext = nil
        currentPlaybackBackend = nil
        progressTracker.reset()
        ttsKitSampleBuffer.reset()
        miniPlayerState.reset(sampleCount: Self.waveformDisplaySampleCount)
        state = .idle
    }

    private func synthesizeAndEnqueueAudioClips(
        text: String,
        config: SynthesisConfig,
        messageID: UUID
    ) async throws {
        try await TextToSpeechSynthesisExecutor.synthesize(
            text: text,
            config: config,
            onQueuedClip: { [weak self] clip in
                self?.enqueueClipIfCurrent(clip, messageID: messageID)
            },
            onTTSKitSamples: { [weak self] samples, sampleRate in
                self?.appendTTSKitGeneratedSamples(
                    samples,
                    sampleRate: sampleRate,
                    messageID: messageID
                )
            },
            onTTSKitFinished: { [weak self] in
                self?.flushPendingTTSKitSamplesIfNeeded(messageID: messageID, force: true)
            }
        )
    }

    private func enqueueClipIfCurrent(_ clip: TextToSpeechQueuedClip, messageID: UUID, updateMetrics: Bool = true) {
        guard currentMessageID == messageID else { return }

        queue.append(clip)
        if updateMetrics {
            if progressTracker.recordGeneratedClip(clip) {
                refreshDisplayedWaveform()
            }
            updatePublishedPlaybackMetrics(currentTime: miniPlayerState.clipCurrentTime)
        }

        if case .generating(let id) = state, id == messageID {
            state = .playing(messageID: messageID)
        }

        if case .playing(let id) = state, id == messageID {
            playNextClipIfNeeded()
        }
    }

    private func completeSynthesisIfCurrent(messageID: UUID) {
        guard currentMessageID == messageID else { return }

        synthesisTask = nil
        didFinishSynthesis = true

        if case .generating(let id) = state, id == messageID {
            state = .playing(messageID: messageID)
        }

        if case .playing(let id) = state, id == messageID {
            playNextClipIfNeeded()
        }
    }

    private func failSynthesisIfCurrent(messageID: UUID, error: Error) {
        guard currentMessageID == messageID else { return }

        currentErrorHandler?(error)
        stop()
    }

    private func finishPlaybackSession() {
        stop()
    }

    private func playNextClipIfNeeded() {
        guard case .playing = state else { return }
        guard let messageID = currentMessageID else {
            stop()
            return
        }

        if player != nil {
            return
        }

        guard !queue.isEmpty else {
            if didFinishSynthesis {
                finishPlaybackSession()
            }
            return
        }

        guard let clip = queue.popFirst() else { return }
        do {
            let audioPlayer = try AVAudioPlayer(data: clip.audioData)
            audioPlayer.delegate = self
            audioPlayer.prepareToPlay()
            player = audioPlayer
            activeClip = clip
            state = .playing(messageID: messageID)
            updateQueuedPlaybackMetrics()
            audioPlayer.play()
            startMeteringTimer()
        } catch {
            currentErrorHandler?(error)
            stop()
        }
    }

    private func startMeteringTimer() {
        stopMeteringTimer()
        meteringTimer = Timer.scheduledTimer(withTimeInterval: Self.playbackRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollMeteringData()
            }
        }
    }

    private func stopMeteringTimer() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }

    private func pollMeteringData() {
        switch currentPlaybackBackend {
        case .queuedClips:
            updateQueuedPlaybackMetrics()
        case .nativeTTSKit:
            Task { [weak self] in
                guard let self else { return }
                let currentTime = await TTSKitService.shared.currentPlaybackTime()
                await MainActor.run {
                    guard self.currentPlaybackBackend == .nativeTTSKit else { return }
                    self.updatePublishedPlaybackMetrics(currentTime: currentTime)
                }
            }
        case .none:
            break
        }
    }

    private func appendTTSKitGeneratedSamples(
        _ samples: [Float],
        sampleRate: Int,
        messageID: UUID
    ) {
        guard currentMessageID == messageID else { return }
        guard let appendResult = ttsKitSampleBuffer.append(
            samples,
            sampleRate: sampleRate,
            secondsPerPeak: TextToSpeechSynthesisExecutor.waveformSecondsPerPeak
        ) else {
            return
        }

        if progressTracker.recordGeneratedAudio(
            duration: appendResult.duration,
            waveformPeaks: appendResult.waveformPeaks
        ) {
            refreshDisplayedWaveform()
        }
        updatePublishedPlaybackMetrics(currentTime: miniPlayerState.clipCurrentTime)
        flushPendingTTSKitSamplesIfNeeded(messageID: messageID, force: false)
    }

    private func flushPendingTTSKitSamplesIfNeeded(messageID: UUID, force: Bool) {
        guard currentMessageID == messageID else { return }

        let shouldPrimePlayback = player == nil && queue.isEmpty
        guard ttsKitSampleBuffer.shouldFlush(
            force: force,
            shouldPrimePlayback: shouldPrimePlayback,
            initialBatchDuration: Self.ttsKitInitialBatchDuration,
            clipBatchDuration: Self.ttsKitClipBatchDuration
        ) else {
            return
        }

        guard let clip = ttsKitSampleBuffer.drainQueuedClip() else { return }
        enqueueClipIfCurrent(clip, messageID: messageID, updateMetrics: false)
    }

    private func updateQueuedPlaybackMetrics() {
        guard let player else {
            updatePublishedPlaybackMetrics(currentTime: progressTracker.queuedPlaybackTime(activeClipCurrentTime: nil))
            return
        }
        updatePublishedPlaybackMetrics(
            currentTime: progressTracker.queuedPlaybackTime(activeClipCurrentTime: player.currentTime)
        )
    }

    private func updatePublishedPlaybackMetrics(currentTime: TimeInterval) {
        miniPlayerState.update(metrics: progressTracker.publishedMetrics(currentTime: currentTime))
    }

    private func refreshDisplayedWaveform() {
        miniPlayerState.updateWaveform(
            progressTracker.displayedWaveformPeaks(targetCount: Self.waveformDisplaySampleCount)
        )
    }

}

extension TextToSpeechPlaybackManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.player === player {
                self.player = nil
            }
            if let activeClip = self.activeClip {
                self.progressTracker.recordPlayedClip(activeClip)
                self.activeClip = nil
                self.updatePublishedPlaybackMetrics(
                    currentTime: self.progressTracker.queuedPlaybackTime(activeClipCurrentTime: nil)
                )
            }
            playNextClipIfNeeded()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.player === player {
                self.player = nil
            }
            let err = error ?? LLMError.providerError(code: "audio_decode_error", message: "Failed to decode audio.")
            currentErrorHandler?(err)
            stop()
        }
    }
}
