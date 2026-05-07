import SwiftUI

struct ContentViewTTSMiniPlayerOverlay: View {
    @ObservedObject var manager: TextToSpeechPlaybackManager
    let isEnabled: Bool
    let selectedConversationID: UUID?
    let onNavigate: (UUID) -> Void

    private var isVisible: Bool {
        isEnabled && manager.state != .idle
    }

    var body: some View {
        Group {
            if isVisible, let context = manager.playbackContext {
                TTSMiniPlayerView(
                    manager: manager,
                    onNavigate: context.conversationID == selectedConversationID ? nil : onNavigate
                )
                .frame(width: TTSMiniPlayerMetrics.width, height: TTSMiniPlayerMetrics.height)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, TTSMiniPlayerMetrics.topOffset)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.92, anchor: .top)
                            .combined(with: .opacity)
                            .combined(with: .offset(y: -8)),
                        removal: .scale(scale: 0.96, anchor: .top)
                            .combined(with: .opacity)
                    )
                )
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: isVisible)
    }
}
