import XCTest
@testable import Jin

final class AgentModeCommandPrefixSupportTests: XCTestCase {
    func testNormalizedPrefixTrimsWhitespaceAndRejectsBlankValues() {
        XCTAssertEqual(AgentModeCommandPrefixSupport.normalizedPrefix(" \n npm run\t "), "npm run")
        XCTAssertNil(AgentModeCommandPrefixSupport.normalizedPrefix(" \n\t "))
    }

    func testCanAddPrefixRequiresNonBlankPrefix() {
        XCTAssertTrue(AgentModeCommandPrefixSupport.canAddPrefix(" swift test "))
        XCTAssertFalse(AgentModeCommandPrefixSupport.canAddPrefix(" \n\t "))
    }

    func testAddingPrefixAppendsTrimmedUniquePrefix() {
        XCTAssertEqual(
            AgentModeCommandPrefixSupport.addingPrefix(
                " \n swift test\t ",
                to: ["git status"]
            ),
            ["git status", "swift test"]
        )
    }

    func testAddingPrefixKeepsExistingOrderForBlankOrDuplicatePrefix() {
        XCTAssertEqual(
            AgentModeCommandPrefixSupport.addingPrefix(" \n\t ", to: ["git status"]),
            ["git status"]
        )
        XCTAssertEqual(
            AgentModeCommandPrefixSupport.addingPrefix(" git status ", to: ["git status"]),
            ["git status"]
        )
    }

    func testRemovingPrefixRemovesExactMatchesOnly() {
        XCTAssertEqual(
            AgentModeCommandPrefixSupport.removingPrefix(
                "git status",
                from: ["git", "git status", "git status --short"]
            ),
            ["git", "git status --short"]
        )
    }

    func testShouldShowResetToDefaultsUsesExactOrderedComparison() {
        let defaults = ["git status", "swift test"]

        XCTAssertFalse(
            AgentModeCommandPrefixSupport.shouldShowResetToDefaults(
                currentPrefixes: defaults,
                defaultPrefixes: defaults
            )
        )
        XCTAssertTrue(
            AgentModeCommandPrefixSupport.shouldShowResetToDefaults(
                currentPrefixes: defaults.reversed(),
                defaultPrefixes: defaults
            )
        )
    }
}
