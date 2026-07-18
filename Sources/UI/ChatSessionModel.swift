import Foundation
import Observation

/// High-churn chat session state owned outside `ChatView`'s giant `@State` surface.
///
/// Sheet drafts and pure presentation flags remain on the view for now; this model
/// holds generation controls, drafts, and error state that many extensions share.
@Observable
@MainActor
final class ChatSessionModel {
    var controls = GenerationControls()
    var draftAttachments: [DraftAttachment] = []
    var draftQuotes: [DraftQuote] = []
    var remoteVideoInputURLText = ""
    var perMessageMCPServerIDs: Set<String> = []
    var currentContextUsageEstimate: ChatContextUsageEstimate?
    var errorMessage: String?
    var showingError = false

    func presentError(_ message: String) {
        errorMessage = message
        showingError = true
    }

    func clearError() {
        showingError = false
        errorMessage = nil
    }
}
