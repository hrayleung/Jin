import XCTest
@testable import Jin

final class CodeExecutionSheetSupportTests: XCTestCase {
    func testProviderSettingsInfoUsesProviderSpecificCopy() {
        XCTAssertEqual(
            CodeExecutionSheetSupport.providerSettingsInfo(for: .claudeManagedAgents).title,
            "Claude Managed Agents"
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.providerSettingsInfo(for: .gemini).title,
            "Gemini API (AI Studio)"
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.providerSettingsInfo(for: .vertexai).body,
            "Vertex AI code execution has no request-level tuning fields in Jin. Vertex AI documents remain prompt context only: the code execution sandbox does not support file I/O."
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.providerSettingsInfo(for: .xai).body,
            "xAI code execution currently has no additional request parameters exposed in Jin."
        )
    }

    func testProviderSettingsInfoFallsBackToProviderDisplayName() {
        let openRouter = CodeExecutionSheetSupport.providerSettingsInfo(for: .openrouter)

        XCTAssertEqual(openRouter.title, ProviderType.openrouter.displayName)
        XCTAssertEqual(
            openRouter.body,
            "No provider-specific code execution parameters are exposed for this provider."
        )

        let missing = CodeExecutionSheetSupport.providerSettingsInfo(for: nil)
        XCTAssertEqual(missing.title, "Provider")
    }

    func testSummaryTextUsesProviderSpecificCopy() {
        XCTAssertEqual(
            CodeExecutionSheetSupport.summaryText(for: .openai),
            "OpenAI supports request-level container configuration for code interpreter, including memory limits, extra file IDs, and explicit container reuse."
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.summaryText(for: .openaiWebSocket),
            "OpenAI supports request-level container configuration for code interpreter, including memory limits, extra file IDs, and explicit container reuse."
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.summaryText(for: .anthropic),
            "Anthropic supports reusable code execution containers. Supported uploaded files can be attached directly to the sandbox."
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.summaryText(for: .claudeManagedAgents),
            "Claude Managed Agents runs tools inside the selected remote agent environment and session."
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.summaryText(for: .gemini),
            "Gemini supports code execution, but there are no extra request fields to tune here."
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.summaryText(for: .vertexai),
            "Vertex AI supports code execution, but the sandbox does not support file I/O."
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.summaryText(for: .openrouter),
            "Provider-native code execution lets the model write and run code inside a managed sandbox."
        )
    }

    func testProviderDetailTextUsesProviderSpecificCopy() {
        XCTAssertEqual(
            CodeExecutionSheetSupport.providerDetailText(for: .openai),
            "Auto creates a request-scoped container. Existing sends a pre-created container reference."
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.providerDetailText(for: .openaiWebSocket),
            "Auto creates a request-scoped container. Existing sends a pre-created container reference."
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.providerDetailText(for: .anthropic),
            "Claude can reuse a container between requests. Supported uploads are mounted into the sandbox."
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.providerDetailText(for: .claudeManagedAgents),
            "Managed agents provision execution inside the remote session environment selected in thread settings."
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.providerDetailText(for: .gemini),
            "Configuration changes apply only to this conversation."
        )
    }

    func testSupportsConfigurationMatchesConfigurableProviders() {
        XCTAssertTrue(CodeExecutionSheetSupport.supportsConfiguration(for: .openai))
        XCTAssertTrue(CodeExecutionSheetSupport.supportsConfiguration(for: .openaiWebSocket))
        XCTAssertTrue(CodeExecutionSheetSupport.supportsConfiguration(for: .anthropic))
        XCTAssertFalse(CodeExecutionSheetSupport.supportsConfiguration(for: .vertexai))
        XCTAssertFalse(CodeExecutionSheetSupport.supportsConfiguration(for: nil))
    }

    func testDraftValidityRequiresExistingContainerOnlyForOpenAIReuseMode() {
        XCTAssertFalse(
            CodeExecutionSheetSupport.isDraftValid(
                providerType: .openai,
                openAIUseExistingContainer: true,
                openAI: OpenAICodeExecutionOptions(existingContainerID: " ")
            )
        )
        XCTAssertTrue(
            CodeExecutionSheetSupport.isDraftValid(
                providerType: .openaiWebSocket,
                openAIUseExistingContainer: true,
                openAI: OpenAICodeExecutionOptions(existingContainerID: "container-123")
            )
        )
        XCTAssertTrue(
            CodeExecutionSheetSupport.isDraftValid(
                providerType: .openai,
                openAIUseExistingContainer: false,
                openAI: nil
            )
        )
        XCTAssertTrue(
            CodeExecutionSheetSupport.isDraftValid(
                providerType: .anthropic,
                openAIUseExistingContainer: true,
                openAI: nil
            )
        )
    }

    func testBadgeTextMatchesProviderSpecificDisplayRules() {
        XCTAssertNil(
            CodeExecutionSheetSupport.badgeText(
                isEnabled: false,
                providerType: .openai,
                controls: CodeExecutionControls(enabled: true)
            )
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.badgeText(
                isEnabled: true,
                providerType: .openai,
                controls: CodeExecutionControls(
                    enabled: true,
                    openAI: OpenAICodeExecutionOptions(existingContainerID: "container-123")
                )
            ),
            "reuse"
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.badgeText(
                isEnabled: true,
                providerType: .openaiWebSocket,
                controls: CodeExecutionControls(
                    enabled: true,
                    openAI: OpenAICodeExecutionOptions(
                        container: CodeExecutionContainer(type: "auto", memoryLimit: " 4g ")
                    )
                )
            ),
            "4g"
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.badgeText(
                isEnabled: true,
                providerType: .anthropic,
                controls: CodeExecutionControls(
                    enabled: true,
                    anthropic: AnthropicCodeExecutionOptions(containerID: "container-abc")
                )
            ),
            "reuse"
        )
        XCTAssertNil(
            CodeExecutionSheetSupport.badgeText(
                isEnabled: true,
                providerType: .vertexai,
                controls: CodeExecutionControls(enabled: true)
            )
        )
    }

    func testHelpTextMatchesProviderSpecificDisplayRules() {
        XCTAssertEqual(
            CodeExecutionSheetSupport.helpText(
                isEnabled: false,
                providerType: .openai,
                controls: CodeExecutionControls(enabled: true)
            ),
            "Code Execution: Off"
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.helpText(
                isEnabled: true,
                providerType: .openai,
                controls: CodeExecutionControls(
                    enabled: true,
                    openAI: OpenAICodeExecutionOptions(existingContainerID: " container-123 ")
                )
            ),
            "Code Execution: Reuse container-123"
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.helpText(
                isEnabled: true,
                providerType: .openaiWebSocket,
                controls: CodeExecutionControls(
                    enabled: true,
                    openAI: OpenAICodeExecutionOptions(
                        container: CodeExecutionContainer(type: "auto", memoryLimit: " 4g ")
                    )
                )
            ),
            "Code Execution: Auto container (4g)"
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.helpText(
                isEnabled: true,
                providerType: .openai,
                controls: CodeExecutionControls(enabled: true)
            ),
            "Code Execution: Auto container"
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.helpText(
                isEnabled: true,
                providerType: .anthropic,
                controls: CodeExecutionControls(
                    enabled: true,
                    anthropic: AnthropicCodeExecutionOptions(containerID: "container-abc")
                )
            ),
            "Code Execution: Reuse container"
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.helpText(
                isEnabled: true,
                providerType: .anthropic,
                controls: CodeExecutionControls(enabled: true)
            ),
            "Code Execution: On"
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.helpText(
                isEnabled: true,
                providerType: .vertexai,
                controls: CodeExecutionControls(enabled: true)
            ),
            "Code Execution: On (no file I/O in sandbox)"
        )
        XCTAssertEqual(
            CodeExecutionSheetSupport.helpText(
                isEnabled: true,
                providerType: .gemini,
                controls: CodeExecutionControls(enabled: true)
            ),
            "Code Execution: On"
        )
    }

    func testParsedOpenAIFileIDsDraftSplitsByCommaAndNewlines() {
        XCTAssertEqual(
            CodeExecutionSheetSupport.parsedOpenAIFileIDsDraft(" file-a,\nfile-b\n\n file-c , "),
            ["file-a", "file-b", "file-c"]
        )
    }

    func testParsedOpenAIFileIDsDraftAllowsDuplicatesLikeExistingDraftParser() {
        XCTAssertEqual(
            CodeExecutionSheetSupport.parsedOpenAIFileIDsDraft("file-a,file-a"),
            ["file-a", "file-a"]
        )
    }

    func testPreparedDraftDefaultsOpenAIProvidersToAutoContainer() {
        let prepared = CodeExecutionSheetSupport.preparedDraft(
            current: nil,
            isEnabled: true,
            providerType: .openai
        )

        XCTAssertTrue(prepared.controls.enabled)
        XCTAssertEqual(prepared.controls.openAI?.container?.type, "auto")
        XCTAssertFalse(prepared.openAIUseExistingContainer)
        XCTAssertEqual(prepared.openAIFileIDsDraft, "")
    }

    func testPreparedDraftPreservesExistingOpenAIContainerDraft() {
        let current = CodeExecutionControls(
            enabled: true,
            openAI: OpenAICodeExecutionOptions(
                container: CodeExecutionContainer(
                    type: "auto",
                    memoryLimit: " 4g ",
                    fileIDs: [" file-a ", "file-b", "file-a"]
                )
            )
        )

        let prepared = CodeExecutionSheetSupport.preparedDraft(
            current: current,
            isEnabled: false,
            providerType: .openaiWebSocket
        )

        XCTAssertTrue(prepared.controls.enabled)
        XCTAssertFalse(prepared.openAIUseExistingContainer)
        XCTAssertEqual(prepared.openAIFileIDsDraft, "file-a\nfile-b")
    }

    func testPreparedDraftDetectsExistingOpenAIContainerReuse() {
        let current = CodeExecutionControls(
            enabled: true,
            openAI: OpenAICodeExecutionOptions(
                container: CodeExecutionContainer(type: "auto", fileIDs: ["file-a"]),
                existingContainerID: " container-123 "
            )
        )

        let prepared = CodeExecutionSheetSupport.preparedDraft(
            current: current,
            isEnabled: false,
            providerType: .openai
        )

        XCTAssertTrue(prepared.openAIUseExistingContainer)
        XCTAssertEqual(prepared.openAIFileIDsDraft, "file-a")
    }

    func testAppliedDraftRequiresOpenAIExistingContainerIDWhenReuseSelected() {
        let draft = CodeExecutionControls(
            enabled: true,
            openAI: OpenAICodeExecutionOptions(container: CodeExecutionContainer(type: "auto"))
        )

        let applied = CodeExecutionSheetSupport.appliedDraft(
            draft,
            providerType: .openai,
            openAIUseExistingContainer: true,
            openAIFileIDsDraft: ""
        )

        XCTAssertFalse(applied.isValid)
        XCTAssertEqual(applied.errorMessage, "Enter an OpenAI container ID.")
        XCTAssertEqual(applied.controls.openAI?.container?.type, "auto")
    }

    func testAppliedDraftNormalizesOpenAIExistingContainerReuse() {
        let draft = CodeExecutionControls(
            enabled: true,
            openAI: OpenAICodeExecutionOptions(
                container: CodeExecutionContainer(type: "auto", memoryLimit: "4g"),
                existingContainerID: " container-123 "
            )
        )

        let applied = CodeExecutionSheetSupport.appliedDraft(
            draft,
            providerType: .openaiWebSocket,
            openAIUseExistingContainer: true,
            openAIFileIDsDraft: "file-a"
        )

        XCTAssertTrue(applied.isValid)
        XCTAssertEqual(applied.controls.openAI?.existingContainerID, "container-123")
        XCTAssertNil(applied.controls.openAI?.container)
    }

    func testAppliedDraftNormalizesOpenAIAutoContainerFileIDs() {
        let draft = CodeExecutionControls(
            enabled: true,
            openAI: OpenAICodeExecutionOptions(
                container: CodeExecutionContainer(type: "manual", memoryLimit: " 4g "),
                existingContainerID: "container-123"
            )
        )

        let applied = CodeExecutionSheetSupport.appliedDraft(
            draft,
            providerType: .openai,
            openAIUseExistingContainer: false,
            openAIFileIDsDraft: " file-a,\nfile-b\nfile-a "
        )

        XCTAssertTrue(applied.isValid)
        XCTAssertNil(applied.controls.openAI?.existingContainerID)
        XCTAssertEqual(applied.controls.openAI?.container?.type, "auto")
        XCTAssertEqual(applied.controls.openAI?.container?.memoryLimit, "4g")
        XCTAssertEqual(applied.controls.openAI?.container?.fileIDs, ["file-a", "file-b"])
    }

    func testAppliedDraftNormalizesAnthropicContainerID() {
        let draft = CodeExecutionControls(
            enabled: true,
            anthropic: AnthropicCodeExecutionOptions(containerID: " container-abc ")
        )

        let applied = CodeExecutionSheetSupport.appliedDraft(
            draft,
            providerType: .anthropic,
            openAIUseExistingContainer: false,
            openAIFileIDsDraft: ""
        )

        XCTAssertTrue(applied.isValid)
        XCTAssertEqual(applied.controls.anthropic?.containerID, "container-abc")
    }

    func testAppliedControlsWritesNormalizedCodeExecutionIntoGenerationControls() {
        let controls = GenerationControls(
            temperature: 0.4,
            codeExecution: CodeExecutionControls(enabled: false)
        )
        let draft = CodeExecutionControls(
            enabled: true,
            openAI: OpenAICodeExecutionOptions(
                container: CodeExecutionContainer(type: "manual", memoryLimit: " 4g ")
            )
        )

        let applied = CodeExecutionSheetSupport.appliedControls(
            draft,
            to: controls,
            providerType: .openai,
            openAIUseExistingContainer: false,
            openAIFileIDsDraft: " file-a,\nfile-b\nfile-a "
        )

        XCTAssertTrue(applied.isValid)
        XCTAssertEqual(applied.controls.temperature, 0.4)
        XCTAssertTrue(applied.controls.codeExecution?.enabled == true)
        XCTAssertEqual(applied.controls.codeExecution?.openAI?.container?.type, "auto")
        XCTAssertEqual(applied.controls.codeExecution?.openAI?.container?.memoryLimit, "4g")
        XCTAssertEqual(applied.controls.codeExecution?.openAI?.container?.fileIDs, ["file-a", "file-b"])
        XCTAssertEqual(applied.codeExecution.openAI?.container?.fileIDs, ["file-a", "file-b"])
    }

    func testAppliedControlsLeavesGenerationControlsUnchangedWhenDraftInvalid() {
        let controls = GenerationControls(
            codeExecution: CodeExecutionControls(
                enabled: true,
                openAI: OpenAICodeExecutionOptions(
                    container: CodeExecutionContainer(type: "auto", memoryLimit: "1g")
                )
            )
        )
        let draft = CodeExecutionControls(
            enabled: true,
            openAI: OpenAICodeExecutionOptions(container: CodeExecutionContainer(type: "auto"))
        )

        let applied = CodeExecutionSheetSupport.appliedControls(
            draft,
            to: controls,
            providerType: .openai,
            openAIUseExistingContainer: true,
            openAIFileIDsDraft: ""
        )

        XCTAssertFalse(applied.isValid)
        XCTAssertEqual(applied.errorMessage, "Enter an OpenAI container ID.")
        XCTAssertEqual(applied.controls.codeExecution?.openAI?.container?.memoryLimit, "1g")
        XCTAssertEqual(applied.codeExecution.openAI?.container?.type, "auto")
    }
}
