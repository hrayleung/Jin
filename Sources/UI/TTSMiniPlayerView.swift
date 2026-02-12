import SwiftUI

struct TTSMiniPlayerView: View {
    @ObservedObject var manager: TextToSpeechPlaybackManager
    let onNavigate: (UUID) -> Void

    private var isPlaying: Bool {
        if case .playing = manager.state { return true }
        return false
    }

    private var isPaused: Bool {
        if case .paused = manager.state { return true }
        return false
    }

    private var isGenerating: Bool {
        if case .generating = manager.state { return true }
        return false
    }

    private var activeMessageID: UUID? {
        switch manager.state {
        case .generating(let id), .playing(let id), .paused(let id):
            return id
        case .idle:
            return nil
        }
    }

    var body: some View {
        HStack(spacing: JinSpacing.medium) {
            speakerIcon

            infoArea

            Spacer(minLength: 0)

            controlButtons
        }
        .padding(.horizontal, JinSpacing.large)
        .padding(.vertical, JinSpacing.small + 2)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(JinSemanticColor.separator.opacity(0.45))
                .frame(height: JinStrokeWidth.hairline)
        }
    }

    @ViewBuilder
    private var speakerIcon: some View {
        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            .frame(width: 20)
    }

    @ViewBuilder
    private var infoArea: some View {
        if let context = manager.playbackContext {
            Button {
                onNavigate(context.conversationID)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.conversationTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Text(context.textPreview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var controlButtons: some View {
        HStack(spacing: JinSpacing.small) {
            if isGenerating {
                ProgressView()
                    .controlSize(.small)
            } else if let messageID = activeMessageID {
                Button {
                    if isPlaying {
                        manager.pause(messageID: messageID)
                    } else if isPaused {
                        manager.resume(messageID: messageID)
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "Pause" : "Resume")
            }

            Button {
                manager.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Stop")
        }
    }
}
