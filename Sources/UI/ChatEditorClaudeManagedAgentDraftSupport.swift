import Foundation

extension ChatEditorDraftSupport {
    static func applyClaudeManagedAgentSessionSettingsDraft(
        agentIDDraft: String,
        environmentIDDraft: String,
        agentDisplayNameDraft: String,
        environmentDisplayNameDraft: String,
        controls: GenerationControls
    ) -> Result<GenerationControls, ChatEditorDraftError> {
        var updatedControls = controls
        let agentID = agentIDDraft.trimmedNonEmpty
        let environmentID = environmentIDDraft.trimmedNonEmpty

        if (agentID == nil) != (environmentID == nil) {
            return .failure(.message("Enter both Agent ID and Environment ID, or leave both blank."))
        }

        updatedControls.claudeManagedAgentID = agentID
        updatedControls.claudeManagedEnvironmentID = environmentID
        updatedControls.claudeManagedAgentDisplayName = agentDisplayNameDraft.trimmedNonEmpty
        updatedControls.claudeManagedEnvironmentDisplayName = environmentDisplayNameDraft.trimmedNonEmpty

        if agentID == nil || environmentID == nil {
            updatedControls.clearClaudeManagedAgentSessionState()
        }

        return .success(updatedControls)
    }
}
