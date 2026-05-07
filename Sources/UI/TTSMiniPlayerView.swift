import AppKit
import SwiftUI

enum TTSMiniPlayerMetrics {
    static let width: CGFloat = 290
    static let height: CGFloat = 40
    static let topOffset: CGFloat = 52
    static let waveformWidth: CGFloat = 80
    static let trailingActionsMinSpacing: CGFloat = 18
    static let horizontalPadding: CGFloat = 14
    static let trailingControlsPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 6
}

struct TTSMiniPlayerView: NSViewRepresentable {
    let manager: TextToSpeechPlaybackManager
    let onNavigate: ((UUID) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager, onNavigate: onNavigate)
    }

    func makeNSView(context: Context) -> TTSMiniPlayerNativeView {
        let view = TTSMiniPlayerNativeView()
        context.coordinator.attach(view)
        return view
    }

    func updateNSView(_ nsView: TTSMiniPlayerNativeView, context: Context) {
        context.coordinator.update(manager: manager, onNavigate: onNavigate, view: nsView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TTSMiniPlayerNativeView, context: Context) -> CGSize? {
        CGSize(width: TTSMiniPlayerMetrics.width, height: TTSMiniPlayerMetrics.height)
    }
}
