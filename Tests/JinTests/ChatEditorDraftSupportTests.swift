import XCTest
@testable import Jin

final class ChatEditorDraftSupportTests: XCTestCase {
    func testApplyClaudeManagedAgentSessionSettingsDraftRequiresBothAgentAndEnvironment() {
        let result = ChatEditorDraftSupport.applyClaudeManagedAgentSessionSettingsDraft(
            agentIDDraft: "agent_123",
            environmentIDDraft: "",
            agentDisplayNameDraft: "Build Agent",
            environmentDisplayNameDraft: "",
            controls: GenerationControls()
        )

        switch result {
        case .success:
            XCTFail("Expected validation failure when only one managed agent identifier is provided.")
        case .failure(let error):
            XCTAssertEqual(error.localizedDescription, "Enter both Agent ID and Environment ID, or leave both blank.")
        }
    }

    func testApplyClaudeManagedAgentSessionSettingsDraftNormalizesConfiguredValues() {
        let result = ChatEditorDraftSupport.applyClaudeManagedAgentSessionSettingsDraft(
            agentIDDraft: " agent_123 ",
            environmentIDDraft: " env_456 ",
            agentDisplayNameDraft: " Build Agent ",
            environmentDisplayNameDraft: " macOS Workspace ",
            controls: GenerationControls()
        )

        switch result {
        case .success(let controls):
            XCTAssertEqual(controls.claudeManagedAgentID, "agent_123")
            XCTAssertEqual(controls.claudeManagedEnvironmentID, "env_456")
            XCTAssertEqual(controls.claudeManagedAgentDisplayName, "Build Agent")
            XCTAssertEqual(controls.claudeManagedEnvironmentDisplayName, "macOS Workspace")
        case .failure(let error):
            XCTFail("Unexpected validation error: \(error.localizedDescription)")
        }
    }
}
