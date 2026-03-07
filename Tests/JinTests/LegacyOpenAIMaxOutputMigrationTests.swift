import XCTest
@testable import Jin

final class LegacyOpenAIMaxOutputMigrationTests: XCTestCase {
    func testMigratedControlsClearsLegacy4096ForOpenAIWhenAssistantUsesModelDefault() {
        let controls = GenerationControls(maxTokens: 4096)

        let migrated = LegacyOpenAIMaxOutputMigration.migratedControlsIfNeeded(
            controls,
            providerType: .openai,
            modelID: "gpt-5.4",
            assistantMaxOutputTokens: nil
        )

        XCTAssertNotNil(migrated)
        XCTAssertNil(migrated?.maxTokens)
    }

    func testMigratedControlsKeepsManual4096WhenAssistantExplicitlySetsIt() {
        let controls = GenerationControls(maxTokens: 4096)

        let migrated = LegacyOpenAIMaxOutputMigration.migratedControlsIfNeeded(
            controls,
            providerType: .openai,
            modelID: "gpt-5.4",
            assistantMaxOutputTokens: 4096
        )

        XCTAssertNil(migrated)
    }

    func testMigratedControlsClearsLegacy4096ForOpenAIWebSocketWhenAssistantUsesModelDefault() {
        let controls = GenerationControls(maxTokens: 4096)

        let migrated = LegacyOpenAIMaxOutputMigration.migratedControlsIfNeeded(
            controls,
            providerType: .openaiWebSocket,
            modelID: "gpt-5.4",
            assistantMaxOutputTokens: nil
        )

        XCTAssertNotNil(migrated)
        XCTAssertNil(migrated?.maxTokens)
    }

    func testMigratedControlsKeepsManual4096ForOpenAIWebSocketWhenAssistantExplicitlySetsIt() {
        let controls = GenerationControls(maxTokens: 4096)

        let migrated = LegacyOpenAIMaxOutputMigration.migratedControlsIfNeeded(
            controls,
            providerType: .openaiWebSocket,
            modelID: "gpt-5.4",
            assistantMaxOutputTokens: 4096
        )

        XCTAssertNil(migrated)
    }

    func testShouldClearAssistantMaxOutputOnlyForDefaultAssistantLegacyValue() {
        XCTAssertTrue(LegacyOpenAIMaxOutputMigration.shouldClearAssistantMaxOutputTokens(4096, assistantID: "default"))
        XCTAssertFalse(LegacyOpenAIMaxOutputMigration.shouldClearAssistantMaxOutputTokens(4096, assistantID: "assistant-1"))
        XCTAssertFalse(LegacyOpenAIMaxOutputMigration.shouldClearAssistantMaxOutputTokens(8192, assistantID: "default"))
    }
}
