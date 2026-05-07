import XCTest
@testable import Jin

final class AgentApprovalPresentationSupportTests: XCTestCase {
    func testRequestDescriptionMatchesApprovalKind() {
        XCTAssertEqual(
            AgentApprovalPresentationSupport.requestDescription(
                for: .shellCommand(command: "rm tmp", cwd: "/repo")
            ),
            "The agent wants to execute a shell command that is not in the allowed command list."
        )
        XCTAssertEqual(
            AgentApprovalPresentationSupport.requestDescription(
                for: .fileWrite(path: "README.md", preview: "content")
            ),
            "The agent wants to create or overwrite a file."
        )
        XCTAssertEqual(
            AgentApprovalPresentationSupport.requestDescription(
                for: .fileEdit(path: "README.md", oldText: "old", newText: "new")
            ),
            "The agent wants to modify an existing file."
        )
    }
}
