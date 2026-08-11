import Collections
import Foundation
import AVFoundation
import CoreGraphics

@MainActor
final class TextToSpeechPlaybackManager: NSObject, ObservableObject {
    static let waveformDisplaySampleCount = 56
    private static let playbackRefreshInterval: TimeInterval = 1.0 / 15.0

    @Published private(set) var state: State = .idle
    @Published private(set) var playbackContext: PlaybackContext?
    let miniPlayerState = TTSMiniPlayerState(sampleCount: 56)

    private var synthesisTask: Task<Void, Never>?
    private var player: AVAudioPlayer?
    /// Set only for the streaming providers; the clip queue below stays empty in that mode.
    private var streamingPlayer: TextToSpeechStreamingAudioPlayer?
    private var queue: Deque<TextToSpeechQueuedClip> = []
    private var activeClip: TextToSpeechQueuedClip?
    private var currentMessageID: UUID?
    private var currentErrorHandler: ((Error) -> Void)?
    private var didFinishSynthesis = true
    private var meteringTimer: Timer?
    private var progressTracker = TextToSpeechPlaybackProgressTracker()

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
            text: text
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

        if let streamingPlayer {
            streamingPlayer.pause()
            updateQueuedPlaybackMetrics()
        } else if let player, player.isPlaying {
            player.pause()
            updateQueuedPlaybackMetrics()
        }

        stopMeteringTimer()
        state = .paused(messageID: messageID)
    }

    func resume(messageID: UUID) {
        guard case .paused(let id) = state, id == messageID else { return }

        state = .playing(messageID: messageID)

        if let streamingPlayer {
            streamingPlayer.resume()
            startMeteringTimer()
            return
        }

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
        synthesisTask?.cancel()
        synthesisTask = nil

        stopMeteringTimer()
        player?.stop()
        player = nil
        streamingPlayer?.stop()
        streamingPlayer = nil
        queue = []
        activeClip = nil
        currentMessageID = nil
        currentErrorHandler = nil
        didFinishSynthesis = true
        playbackContext = nil
        progressTracker.reset()
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
            onEvent: { [weak self] event in
                try self?.handleSynthesisEvent(event, messageID: messageID)
            }
        )
    }

    private func handleSynthesisEvent(
        _ event: TextToSpeechSynthesisEvent,
        messageID: UUID
    ) throws {
        guard currentMessageID == messageID else { return }

        switch event {
        case .clip(let clip):
            enqueueClipIfCurrent(clip, messageID: messageID)
        case .streamStarted(let sampleRate):
            try startStreamingPlayback(sampleRate: sampleRate, messageID: messageID)
        case .streamedPCM(let audio):
            appendStreamedAudio(audio, messageID: messageID)
        }
    }

    private func startStreamingPlayback(sampleRate: Double, messageID: UUID) throws {
        guard streamingPlayer == nil else { return }

        let player = TextToSpeechStreamingAudioPlayer()
        try player.start(sampleRate: sampleRate) { [weak self] in
            guard let self, self.currentMessageID == messageID else { return }
            self.finishPlaybackSession()
        }
        streamingPlayer = player
    }

    private func appendStreamedAudio(_ audio: Data, messageID: UUID) {
        guard let streamingPlayer,
              let appended = streamingPlayer.append(pcm16: audio) else {
            return
        }

        if progressTracker.recordGeneratedAudio(
            duration: appended.duration,
            waveformPeaks: appended.waveformPeaks
        ) {
            refreshDisplayedWaveform()
        }

        if case .generating(let id) = state, id == messageID {
            state = .playing(messageID: messageID)
            startMeteringTimer()
        }

        updateQueuedPlaybackMetrics()
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

        if let streamingPlayer {
            // The session ends when the already-scheduled buffers drain, not now.
            streamingPlayer.finishProducing()
            return
        }

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
        // Streaming sessions never populate the clip queue; draining it would end them early.
        guard streamingPlayer == nil else { return }
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
                self?.updateQueuedPlaybackMetrics()
            }
        }
    }

    private func stopMeteringTimer() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }

    private func updateQueuedPlaybackMetrics() {
        if let streamingPlayer {
            updatePublishedPlaybackMetrics(
                currentTime: progressTracker.queuedPlaybackTime(
                    activeClipCurrentTime: streamingPlayer.currentTime
                )
            )
            return
        }

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
