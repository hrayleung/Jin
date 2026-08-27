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

    func testIsSingleExecutionMatchesActivityCount() {
        XCTAssertTrue(
            CodeExecutionTimelineSupport.isSingleExecution([
                activity(id: "one", status: .completed)
            ])
        )
        XCTAssertFalse(
            CodeExecutionTimelineSupport.isSingleExecution([
                activity(id: "one", status: .completed),
                activity(id: "two", status: .completed)
            ])
        )
    }

    func testHeaderStatusUsesQuietSuccessAndRunningCopy() {
        XCTAssertEqual(
            CodeExecutionTimelineSupport.headerStatus(
                for: [activity(id: "running", status: .interpreting)]
            ),
            .init(kind: .running, text: "Running", icon: nil)
        )
        XCTAssertEqual(
            CodeExecutionTimelineSupport.headerStatus(
                for: [activity(id: "write", status: .writingCode)]
            ),
            .init(kind: .running, text: "Writing", icon: nil)
        )
        XCTAssertEqual(
            CodeExecutionTimelineSupport.headerStatus(
                for: [activity(id: "start", status: .inProgress)]
            ),
            .init(kind: .running, text: "Starting", icon: nil)
        )
        XCTAssertEqual(
            CodeExecutionTimelineSupport.headerStatus(
                for: [activity(id: "done", status: .completed)]
            ),
            .init(kind: .success, text: nil, icon: "checkmark.circle.fill")
        )
        XCTAssertEqual(
            CodeExecutionTimelineSupport.headerStatus(
                for: [activity(id: "failed", status: .failed)]
            ),
            .init(kind: .failure, text: "Failed", icon: "xmark.circle.fill")
        )
        XCTAssertEqual(
            CodeExecutionTimelineSupport.headerStatus(
                for: [
                    activity(id: "failed", status: .failed),
                    activity(id: "incomplete", status: .incomplete)
                ]
            ),
            .init(kind: .failure, text: "2 failed", icon: "xmark.circle.fill")
        )
        XCTAssertEqual(
            CodeExecutionTimelineSupport.headerStatus(
                for: [
                    activity(id: "done", status: .completed),
                    activity(id: "failed", status: .failed)
                ]
            ),
            .init(kind: .failure, text: "1 ok / 1 failed", icon: "xmark.circle.fill")
        )
        XCTAssertNil(
            CodeExecutionTimelineSupport.headerStatus(
                for: [activity(id: "unknown", status: .unknown("queued"))]
            )
        )
    }

    func testCollapsedPreviewUsesFirstCodeLineOrRunningPlaceholder() {
        XCTAssertEqual(
            CodeExecutionTimelineSupport.collapsedPreview(
                for: [
                    CodeExecutionActivity(
                        id: "code",
                        status: .completed,
                        code: "\nimport platform\nprint(1)"
                    )
                ]
            ),
            "import platform"
        )
        XCTAssertEqual(
            CodeExecutionTimelineSupport.collapsedPreview(
                for: [activity(id: "write", status: .writingCode)]
            ),
            "Writing code..."
        )
        XCTAssertNil(
            CodeExecutionTimelineSupport.collapsedPreview(
                for: [
                    activity(id: "one", status: .completed, code: "print(1)"),
                    activity(id: "two", status: .completed, code: "print(2)")
                ]
            )
        )
        XCTAssertNil(
            CodeExecutionTimelineSupport.collapsedPreview(
                for: [activity(id: "done", status: .completed)]
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
        status: CodeExecutionStatus,
        code: String? = nil
    ) -> CodeExecutionActivity {
        CodeExecutionActivity(id: id, status: status, code: code)
    }
}
