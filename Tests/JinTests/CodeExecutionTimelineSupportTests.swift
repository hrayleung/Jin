import XCTest
@testable import Jin

final class CodeExecutionTimelineSupportTests: XCTestCase {
    func testInitialExpansionFollowsDisplayModeAndStreamingState() {
        XCTAssertTrue(
            CodeExecutionTimelineSupport.initialExpansion(
                isStreaming: true,
                displayMode: .expanded
            )
        )
        XCTAssertTrue(
            CodeExecutionTimelineSupport.initialExpansion(
                isStreaming: true,
                displayMode: .collapseOnComplete
            )
        )
        XCTAssertFalse(
            CodeExecutionTimelineSupport.initialExpansion(
                isStreaming: true,
                displayMode: .alwaysCollapsed
            )
        )
        XCTAssertTrue(
            CodeExecutionTimelineSupport.initialExpansion(
                isStreaming: false,
                displayMode: .expanded
            )
        )
        XCTAssertFalse(
            CodeExecutionTimelineSupport.initialExpansion(
                isStreaming: false,
                displayMode: .collapseOnComplete
            )
        )
        XCTAssertFalse(
            CodeExecutionTimelineSupport.initialExpansion(
                isStreaming: false,
                displayMode: .alwaysCollapsed
            )
        )
    }

    func testStreamingChangeExpansionMatchesExistingModeRules() {
        XCTAssertEqual(
            CodeExecutionTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: true,
                displayMode: .expanded
            ),
            true
        )
        XCTAssertEqual(
            CodeExecutionTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: true,
                displayMode: .collapseOnComplete
            ),
            true
        )
        XCTAssertNil(
            CodeExecutionTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: true,
                displayMode: .alwaysCollapsed
            )
        )
        XCTAssertEqual(
            CodeExecutionTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: false,
                displayMode: .collapseOnComplete
            ),
            false
        )
        XCTAssertNil(
            CodeExecutionTimelineSupport.shouldExpandAfterStreamingChange(
                isStreaming: false,
                displayMode: .expanded
            )
        )
    }

    func testHasActiveExecutionRecognizesRunningStatusesOnly() {
        XCTAssertTrue(
            CodeExecutionTimelineSupport.hasActiveExecution([
                activity(id: "start", status: .inProgress)
            ])
        )
        XCTAssertTrue(
            CodeExecutionTimelineSupport.hasActiveExecution([
                activity(id: "write", status: .writingCode)
            ])
        )
        XCTAssertTrue(
            CodeExecutionTimelineSupport.hasActiveExecution([
                activity(id: "run", status: .interpreting)
            ])
        )
        XCTAssertFalse(
            CodeExecutionTimelineSupport.hasActiveExecution([
                activity(id: "done", status: .completed),
                activity(id: "failed", status: .failed),
                activity(id: "unknown", status: .unknown("queued"))
            ])
        )
    }

    func testCountsClassifyExecutionStatuses() {
        XCTAssertEqual(
            CodeExecutionTimelineSupport.counts(
                for: [
                    activity(id: "start", status: .inProgress),
                    activity(id: "write", status: .writingCode),
                    activity(id: "run", status: .interpreting),
                    activity(id: "done", status: .completed),
                    activity(id: "failed", status: .failed),
                    activity(id: "incomplete", status: .incomplete),
                    activity(id: "unknown", status: .unknown("queued"))
                ]
            ),
            .init(active: 3, completed: 1, failed: 2)
        )
    }

    func testHeaderTitlePluralizesCodeExecutionCount() {
        XCTAssertEqual(CodeExecutionTimelineSupport.headerTitle(activityCount: 0), "0 Code Executions")
        XCTAssertEqual(CodeExecutionTimelineSupport.headerTitle(activityCount: 1), "Code Execution")
        XCTAssertEqual(CodeExecutionTimelineSupport.headerTitle(activityCount: 2), "2 Code Executions")
    }

    func testCompactStatusSummarizesCompletedAndFailedActivities() {
        XCTAssertNil(
            CodeExecutionTimelineSupport.compactStatus(
                for: [activity(id: "running", status: .interpreting)]
            )
        )
        XCTAssertEqual(
            CodeExecutionTimelineSupport.compactStatus(
                for: [activity(id: "done", status: .completed)]
            ),
            .init(text: "Done", icon: "checkmark.circle", kind: .success)
        )
        XCTAssertEqual(
            CodeExecutionTimelineSupport.compactStatus(
                for: [activity(id: "failed", status: .failed)]
            ),
            .init(text: "Failed", icon: "xmark.circle", kind: .failure)
        )
        XCTAssertEqual(
            CodeExecutionTimelineSupport.compactStatus(
                for: [
                    activity(id: "failed", status: .failed),
                    activity(id: "incomplete", status: .incomplete)
                ]
            ),
            .init(text: "2 failed", icon: "xmark.circle", kind: .failure)
        )
        XCTAssertEqual(
            CodeExecutionTimelineSupport.compactStatus(
                for: [
                    activity(id: "done", status: .completed),
                    activity(id: "failed", status: .failed)
                ]
            ),
            .init(text: "1 ok / 1 failed", icon: "xmark.circle", kind: .failure)
        )
        XCTAssertNil(
            CodeExecutionTimelineSupport.compactStatus(
                for: [activity(id: "unknown", status: .unknown("queued"))]
            )
        )
    }

    func testAnimationSignatureTracksIDsAndStatusDescriptionsInOrder() {
        XCTAssertEqual(
            CodeExecutionTimelineSupport.animationSignature(
                for: [
                    activity(id: "a", status: .writingCode),
                    activity(id: "b", status: .completed)
                ]
            ),
            "a:writingCode|b:completed"
        )
    }

    private func activity(
        id: String,
        status: CodeExecutionStatus
    ) -> CodeExecutionActivity {
        CodeExecutionActivity(id: id, status: status)
    }
}
