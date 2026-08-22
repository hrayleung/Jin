import SwiftUI

// MARK: - Source Video URL

extension ChatView {

    var hasRemoteVideoInputURL: Bool {
        !trimmedRemoteVideoInputURLText.isEmpty
    }

    var remoteVideoInputHelpText: String {
        ComposerRemoteVideoURLSupport.helpText(for: remoteVideoInputURLText)
    }

    /// The only write point for `remoteVideoInputURLText` outside the send
    /// path. Called once, when the editor commits — never per keystroke.
    /// Storing the trimmed value is safe: the send path already snapshots
    /// `trimmedRemoteVideoInputURLText` and restores an already-trimmed value.
    func commitRemoteVideoInputURL(_ raw: String) {
        remoteVideoInputURLText = raw.trimmed
    }

    func clearRemoteVideoInputURL() {
        remoteVideoInputURLText = ""
    }
}
