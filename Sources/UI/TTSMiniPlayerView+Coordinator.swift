import Combine
import Foundation

extension TTSMiniPlayerView {
    @MainActor
    final class Coordinator {
        private var manager: TextToSpeechPlaybackManager
        private var onNavigate: ((UUID) -> Void)?
        private weak var view: TTSMiniPlayerNativeView?
        private var cancellables: Set<AnyCancellable> = []

        init(manager: TextToSpeechPlaybackManager, onNavigate: ((UUID) -> Void)?) {
            self.manager = manager
            self.onNavigate = onNavigate
        }

        func attach(_ view: TTSMiniPlayerNativeView) {
            self.view = view
            configureCallbacks()
            bind()
            applySnapshot()
        }

        func update(
            manager: TextToSpeechPlaybackManager,
            onNavigate: ((UUID) -> Void)?,
            view: TTSMiniPlayerNativeView
        ) {
            self.view = view
            self.onNavigate = onNavigate

            if self.manager !== manager {
                self.manager = manager
                bind()
            }

            configureCallbacks()
            applySnapshot()
        }

        private func bind() {
            cancellables.removeAll()

            manager.$state
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applySnapshot() }
                .store(in: &cancellables)

            manager.$playbackContext
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applySnapshot() }
                .store(in: &cancellables)

            let miniPlayerState = manager.miniPlayerState
            miniPlayerState.$waveformPeaks
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applySnapshot() }
                .store(in: &cancellables)

            miniPlayerState.$clipProgress
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applySnapshot() }
                .store(in: &cancellables)

            miniPlayerState.$clipCurrentTime
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applySnapshot() }
                .store(in: &cancellables)

            miniPlayerState.$clipDuration
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applySnapshot() }
                .store(in: &cancellables)
        }

        private func configureCallbacks() {
            view?.onPrimaryAction = { [weak self] in
                self?.handlePrimaryAction()
            }
            view?.onNavigate = { [weak self] in
                self?.handleNavigate()
            }
            view?.onStop = { [weak self] in
                self?.manager.stop()
            }
        }

        private func handlePrimaryAction() {
            guard let messageID = TTSMiniPlayerSnapshotSupport.activeMessageID(for: manager.state) else { return }

            if case .playing = manager.state {
                manager.pause(messageID: messageID)
            } else if case .paused = manager.state {
                manager.resume(messageID: messageID)
            }
        }

        private func handleNavigate() {
            guard let context = manager.playbackContext else { return }
            onNavigate?(context.conversationID)
        }

        private func applySnapshot() {
            view?.apply(snapshot: snapshot)
        }

        private var snapshot: TTSMiniPlayerSnapshot {
            let miniPlayerState = manager.miniPlayerState
            return TTSMiniPlayerSnapshotSupport.snapshot(
                state: manager.state,
                playbackContext: manager.playbackContext,
                waveformPeaks: miniPlayerState.waveformPeaks,
                progress: miniPlayerState.clipProgress,
                currentTime: miniPlayerState.clipCurrentTime,
                hasNavigateHandler: onNavigate != nil
            )
        }
    }
}
