import AVFoundation
import Foundation

// MARK: - Voice Preview

extension TextToSpeechPluginSettingsView {

    func playSelectedVoicePreview() async {
        guard let url = selectedElevenLabsVoicePreviewURL else { return }

        if isPlayingVoicePreview {
            await MainActor.run {
                voicePreviewPlayer?.stop()
                voicePreviewPlayer = nil
                isPlayingVoicePreview = false
            }
            return
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (data, _) = try await NetworkDebugRequestExecutor.data(
                for: request,
                mode: "tts_voice_preview"
            )
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            await MainActor.run {
                voicePreviewPlayer = player
                isPlayingVoicePreview = true
            }
            player.play()

            // Poll completion state (AVAudioPlayer delegate requires NSObject conformance).
            Task { @MainActor in
                while player.isPlaying {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if voicePreviewPlayer === player {
                    voicePreviewPlayer = nil
                    isPlayingVoicePreview = false
                }
            }
        } catch {
            await MainActor.run {
                statusMessage = error.localizedDescription
                statusIsError = true
                isPlayingVoicePreview = false
            }
        }
    }
}
