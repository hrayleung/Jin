import Foundation

struct ComposerSendButtonPresentation: Equatable {
    let usesCommandReturn: Bool
    let isBusy: Bool
    let canSendDraft: Bool
    let isRecording: Bool
    let isTranscribing: Bool

    var isDisabled: Bool {
        (!canSendDraft && !isBusy) || isRecording || isTranscribing
    }

    var expandedTitle: String {
        isBusy ? "Stop" : "Send"
    }

    var expandedSystemImage: String {
        isBusy ? "stop.fill" : "arrow.up"
    }

    var compactSystemImage: String {
        isBusy ? "stop.circle.fill" : "arrow.up.circle.fill"
    }

    var shortcutGlyph: String {
        usesCommandReturn ? "⌘↩" : "↩"
    }
}
