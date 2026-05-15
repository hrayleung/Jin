import XCTest
@testable import Jin

final class ChatStreamingOrchestratorTests: XCTestCase {
    @MainActor
    private final class ContinuationCallbackRecorder {
        var persistedClaudeManagedSessionState: ClaudeManagedAgentSessionState?
        var persistedClaudeManagedSessionLocalThreadID: UUID?
        var persistedPendingResults: [ClaudeManagedAgentPendingToolResult] = []
        var persistedPendingResultsThreadID: UUID?
        var didPersistPendingResults = false
        var persistedToolMessage: Message?
        var persistedToolThreadID: UUID?
        var persistedToolTurnID: UUID?
        var mergedSearchActivities: (messageID: UUID, activities: [SearchActivity])?
        var autoRenameRequest: (
            provider: ProviderConfig,
            modelID: String,
            history: [Message],
            assistantMessage: Message
        )?
        var appendedManagedAgentInteractionRequest: ManagedAgentInteractionRequest?
        var appendedManagedAgentInteractionThreadID: UUID?
        var onAppendManagedAgentInteraction: (() -> Void)?
    }

    @MainActor
    private func makeContinuationCallbacks(
        recording recorder: ContinuationCallbackRecorder
    ) -> ChatStreamingOrchestrator.SessionCallbacks {
        ChatStreamingOrchestrator.SessionCallbacks(
            persistAssistantMessage: { _, _, _, _, _, _, _ in nil },
            persistToolMessage: { message, localThreadID, localTurnID in
                recorder.persistedToolMessage = message
                recorder.persistedToolThreadID = localThreadID
                recorder.persistedToolTurnID = localTurnID
            },
            persistClaudeManagedSessionState: { state, localThreadID in
                recorder.persistedClaudeManagedSessionState = state
                recorder.persistedClaudeManagedSessionLocalThreadID = localThreadID
            },
            persistClaudeManagedPendingToolResults: { results, localThreadID in
                recorder.didPersistPendingResults = true
                recorder.persistedPendingResults = results
                recorder.persistedPendingResultsThreadID = localThreadID
            },
            appendManagedAgentInteraction: { request, localThreadID in
                recorder.appendedManagedAgentInteractionRequest = request
                recorder.appendedManagedAgentInteractionThreadID = localThreadID
                recorder.onAppendManagedAgentInteraction?()
            },
            mergeSearchActivities: { messageID, activities in
                recorder.mergedSearchActivities = (messageID, activities)
            },
            maybeAutoRename: { provider, modelID, history, assistantMessage in
                recorder.autoRenameRequest = (provider, modelID, history, assistantMessage)
            },
            showError: { _ in },
            endStreamingSession: {},
            onSessionEnd: { _, _, _ in }
        )
    }

    private func makeSessionContext(
        providerType: ProviderType?,
        threadID: UUID = UUID(),
        turnID: UUID? = UUID(),
        chatNamingTarget: (provider: ProviderConfig, modelID: String)? = nil,
        triggeredByUserSend: Bool = false
    ) -> ChatStreamingOrchestrator.SessionContext {
        ChatStreamingOrchestrator.SessionContext(
            conversationID: UUID(),
            threadID: threadID,
            turnID: turnID,
            diagnosticRunID: "test-run-id",
            providerID: "provider",
            providerConfig: nil,
            providerType: providerType,
            modelID: "model",
            modelNameSnapshot: "Model",
            resolvedModelSettings: nil,
            messageSnapshots: [],
            systemPrompt: nil,
            controlsToUse: GenerationControls(),
            shouldTruncateMessages: false,
            maxHistoryMessages: nil,
            modelContextWindow: 4_096,
            reservedOutputTokens: 0,
            mcpServerConfigs: [],
            chatNamingTarget: chatNamingTarget,
            shouldOfferBuiltinSearch: false,
            triggeredByUserSend: triggeredByUserSend,
            networkLogContext: NetworkDebugLogContext()
        )
    }

    func testPrepareHistoryUsesOnlyMatchingThreadSnapshots() throws {
        let threadID = UUID()
        let otherThreadID = UUID()
        let matchingUser = try MessageEntity.fromDomain(
            Message(
                id: UUID(),
                role: .user,
                content: [.text("thread-a user")],
                timestamp: Date(timeIntervalSince1970: 1)
            )
        )
        matchingUser.contextThreadID = threadID

        let otherThreadMessage = try MessageEntity.fromDomain(
            Message(
                id: UUID(),
                role: .assistant,
                content: [.text("thread-b assistant")],
                timestamp: Date(timeIntervalSince1970: 2)
            )
        )
        otherThreadMessage.contextThreadID = otherThreadID

        let matchingAssistant = try MessageEntity.fromDomain(
            Message(
                id: UUID(),
                role: .assistant,
                content: [.text("thread-a assistant")],
                timestamp: Date(timeIntervalSince1970: 3)
            )
        )
        matchingAssistant.contextThreadID = threadID

        let context = ChatStreamingOrchestrator.SessionContext(
            conversationID: UUID(),
            threadID: threadID,
            turnID: nil,
            diagnosticRunID: "test-run-id",
            providerID: "provider",
            providerConfig: nil,
            providerType: nil,
            modelID: "model",
            modelNameSnapshot: "Model",
            resolvedModelSettings: nil,
            messageSnapshots: [
                PersistedMessageSnapshot(otherThreadMessage),
                PersistedMessageSnapshot(matchingAssistant),
                PersistedMessageSnapshot(matchingUser),
            ],
            systemPrompt: "system",
            controlsToUse: GenerationControls(),
            shouldTruncateMessages: false,
            maxHistoryMessages: nil,
            modelContextWindow: 4_096,
            reservedOutputTokens: 0,
            mcpServerConfigs: [],
            chatNamingTarget: nil,
            shouldOfferBuiltinSearch: false,
            triggeredByUserSend: false,
            networkLogContext: NetworkDebugLogContext()
        )

        let history = ChatStreamingOrchestrator.prepareHistory(from: context)
        XCTAssertEqual(history.map { $0.role }, [MessageRole.system, .user, .assistant])
        XCTAssertEqual(history.compactMap { message -> String? in
            guard case .text(let text) = message.content.first else { return nil }
            return text
        }, ["system", "thread-a user", "thread-a assistant"])
    }

    func testHasRenderableAssistantContentRequiresRenderablePayload() {
        XCTAssertFalse(
            ChatStreamingOrchestrator.hasRenderableAssistantContent(
                assistantPartCount: 0,
                searchActivityCount: 0,
                codeExecutionActivityCount: 0
            )
        )
    }

    func testHasRenderableAssistantContentCountsNonTextAssistantOutputs() {
        XCTAssertTrue(
            ChatStreamingOrchestrator.hasRenderableAssistantContent(
                assistantPartCount: 0,
                searchActivityCount: 1,
                codeExecutionActivityCount: 0
            )
        )
        XCTAssertTrue(
            ChatStreamingOrchestrator.hasRenderableAssistantContent(
                assistantPartCount: 0,
                searchActivityCount: 0,
                codeExecutionActivityCount: 1
            )
        )
    }

    func testCompletionNotificationStateKeepsLatestPreviewAndNotifyFlag() {
        var state = ChatStreamingOrchestrator.CompletionNotificationState()

        state.observe(
            ChatStreamingOrchestrator.AssistantPersistenceResult(
                message: nil,
                persistedMessageID: nil,
                hasRenderableContent: true,
                completionPreview: "First"
            )
        )
        state.observe(
            ChatStreamingOrchestrator.AssistantPersistenceResult(
                message: nil,
                persistedMessageID: nil,
                hasRenderableContent: false,
                completionPreview: nil
            )
        )

        XCTAssertFalse(state.shouldNotify)
        XCTAssertEqual(state.preview, "First")

        state.finishWithoutToolContinuation(hasRenderableContent: true)
        XCTAssertTrue(state.shouldNotify)

        state.observe(
            ChatStreamingOrchestrator.AssistantPersistenceResult(
                message: nil,
                persistedMessageID: nil,
                hasRenderableContent: true,
                completionPreview: "Latest"
            )
        )
        XCTAssertEqual(state.preview, "Latest")
    }

    @MainActor
    func testApplyAssistantPersistenceFollowUpAppendsAssistantAndAutoRenamesEligibleUserSend() async {
        let recorder = ContinuationCallbackRecorder()
        let callbacks = makeContinuationCallbacks(recording: recorder)
        let provider = ProviderConfig(id: "openai-provider", name: "OpenAI", type: .openai)
        let context = makeSessionContext(
            providerType: .openai,
            chatNamingTarget: (provider, "gpt-5.2"),
            triggeredByUserSend: true
        )
        let userMessage = Message(role: .user, content: [.text("Hello")])
        let assistantMessage = Message(role: .assistant, content: [.text("Hi")])

        let updatedHistory = await ChatStreamingOrchestrator.applyAssistantPersistenceFollowUp(
            ChatStreamingOrchestrator.AssistantPersistenceResult(
                message: assistantMessage,
                persistedMessageID: UUID(),
                hasRenderableContent: true,
                completionPreview: "Hi"
            ),
            responseHasToolCalls: false,
            history: [userMessage],
            context: context,
            callbacks: callbacks
        )

        XCTAssertEqual(updatedHistory.map(\.id), [userMessage.id, assistantMessage.id])
        XCTAssertEqual(recorder.autoRenameRequest?.provider.id, "openai-provider")
        XCTAssertEqual(recorder.autoRenameRequest?.modelID, "gpt-5.2")
        XCTAssertEqual(recorder.autoRenameRequest?.history.map(\.id), [userMessage.id, assistantMessage.id])
        XCTAssertEqual(recorder.autoRenameRequest?.assistantMessage.id, assistantMessage.id)
    }

    @MainActor
    func testApplyAssistantPersistenceFollowUpSkipsAutoRenameWhenAssistantHasToolCalls() async {
        let recorder = ContinuationCallbackRecorder()
        let callbacks = makeContinuationCallbacks(recording: recorder)
        let provider = ProviderConfig(id: "openai-provider", name: "OpenAI", type: .openai)
        let context = makeSessionContext(
            providerType: .openai,
            chatNamingTarget: (provider, "gpt-5.2"),
            triggeredByUserSend: true
        )
        let assistantMessage = Message(role: .assistant, content: [.text("Calling tool")])

        let updatedHistory = await ChatStreamingOrchestrator.applyAssistantPersistenceFollowUp(
            ChatStreamingOrchestrator.AssistantPersistenceResult(
                message: assistantMessage,
                persistedMessageID: UUID(),
                hasRenderableContent: true,
                completionPreview: "Calling tool"
            ),
            responseHasToolCalls: true,
            history: [],
            context: context,
            callbacks: callbacks
        )

        XCTAssertEqual(updatedHistory.single?.id, assistantMessage.id)
        XCTAssertNil(recorder.autoRenameRequest)
    }

    @MainActor
    func testApplyAssistantPersistenceFollowUpLeavesHistoryWhenAssistantWasNotPersisted() async {
        let recorder = ContinuationCallbackRecorder()
        let callbacks = makeContinuationCallbacks(recording: recorder)
        let context = makeSessionContext(providerType: .openai)
        let userMessage = Message(role: .user, content: [.text("Hello")])

        let updatedHistory = await ChatStreamingOrchestrator.applyAssistantPersistenceFollowUp(
            ChatStreamingOrchestrator.AssistantPersistenceResult(
                message: nil,
                persistedMessageID: nil,
                hasRenderableContent: false,
                completionPreview: nil
            ),
            responseHasToolCalls: false,
            history: [userMessage],
            context: context,
            callbacks: callbacks
        )

        XCTAssertEqual(updatedHistory.single?.id, userMessage.id)
        XCTAssertNil(recorder.autoRenameRequest)
    }

    func testStreamingLoopDiagnosticStateReportsFirstStreamEventOnlyOnce() {
        var state = ChatStreamingOrchestrator.StreamingLoopDiagnosticState()

        XCTAssertEqual(state.firstStreamEventName(.messageStart(id: "message-1")), "messageStart")
        XCTAssertTrue(state.didObserveFirstStreamEvent)
        XCTAssertNil(state.firstStreamEventName(.contentDelta(.text("hello"))))
    }

    func testStreamingLoopDiagnosticStateReportsFirstContentDeltaOnlyOnce() {
        var state = ChatStreamingOrchestrator.StreamingLoopDiagnosticState()

        XCTAssertEqual(state.firstContentDeltaCount("hello"), 5)
        XCTAssertTrue(state.didObserveFirstContentDelta)
        XCTAssertNil(state.firstContentDeltaCount("world"))
    }

    func testStreamingLoopDiagnosticStateSkipsEmptyThinkingAndReportsFirstNonEmptyDeltaOnlyOnce() {
        var state = ChatStreamingOrchestrator.StreamingLoopDiagnosticState()

        XCTAssertNil(state.firstThinkingDeltaCount(""))
        XCTAssertFalse(state.didObserveFirstThinkingDelta)
        XCTAssertEqual(state.firstThinkingDeltaCount("reasoning"), 9)
        XCTAssertTrue(state.didObserveFirstThinkingDelta)
        XCTAssertNil(state.firstThinkingDeltaCount("more reasoning"))
    }

    func testObserveStreamEventUpdatesMetricsAndFirstEventDiagnostics() throws {
        var metricsCollector = StreamingResponseMetricsCollector()
        var diagnostics = ChatStreamingOrchestrator.StreamingLoopDiagnosticState()
        let context = makeSessionContext(providerType: .openai)
        let start = Date(timeIntervalSince1970: 1_000)

        metricsCollector.begin(at: start)

        ChatStreamingOrchestrator.observeStreamEvent(
            .contentDelta(.text("hello")),
            at: start.addingTimeInterval(0.25),
            metricsCollector: &metricsCollector,
            diagnostics: &diagnostics,
            context: context
        )
        ChatStreamingOrchestrator.observeStreamEvent(
            .contentDelta(.text("world")),
            at: start.addingTimeInterval(0.5),
            metricsCollector: &metricsCollector,
            diagnostics: &diagnostics,
            context: context
        )
        metricsCollector.end(at: start.addingTimeInterval(1.0))

        XCTAssertTrue(diagnostics.didObserveFirstStreamEvent)
        let metrics = try XCTUnwrap(metricsCollector.metrics)
        XCTAssertEqual(try XCTUnwrap(metrics.timeToFirstTokenSeconds), 0.25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(metrics.durationSeconds), 1.0, accuracy: 0.0001)
    }

    func testFirstStreamDiagnosticDataPreservesContextAndSpecificFields() {
        let context = makeSessionContext(providerType: .openai)

        let baseData = ChatStreamingOrchestrator.baseStreamDiagnosticData(context: context)
        XCTAssertEqual(baseData["conversationID"], context.conversationID.uuidString)
        XCTAssertEqual(baseData["threadID"], context.threadID.uuidString)
        XCTAssertNil(baseData["event"])
        XCTAssertNil(baseData["textDeltaCount"])
        XCTAssertNil(baseData["thinkingDeltaCount"])

        let eventData = ChatStreamingOrchestrator.firstStreamEventDiagnosticData(
            eventName: "contentDelta",
            context: context
        )
        XCTAssertEqual(eventData["conversationID"], context.conversationID.uuidString)
        XCTAssertEqual(eventData["threadID"], context.threadID.uuidString)
        XCTAssertEqual(eventData["event"], "contentDelta")

        let contentData = ChatStreamingOrchestrator.firstContentDeltaDiagnosticData(
            deltaCount: 5,
            context: context
        )
        XCTAssertEqual(contentData["conversationID"], context.conversationID.uuidString)
        XCTAssertEqual(contentData["threadID"], context.threadID.uuidString)
        XCTAssertEqual(contentData["textDeltaCount"], "5")

        let thinkingData = ChatStreamingOrchestrator.firstThinkingDeltaDiagnosticData(
            deltaCount: 9,
            context: context
        )
        XCTAssertEqual(thinkingData["conversationID"], context.conversationID.uuidString)
        XCTAssertEqual(thinkingData["threadID"], context.threadID.uuidString)
        XCTAssertEqual(thinkingData["thinkingDeltaCount"], "9")
    }

    func testAdapterStreamCreatedDiagnosticDataPreservesContextAndCreationFields() {
        let context = makeSessionContext(providerType: .openai)

        let data = ChatStreamingOrchestrator.adapterStreamCreatedDiagnosticData(
            providerType: .anthropic,
            modelID: "claude-sonnet-test",
            historyCount: 7,
            toolCount: 3,
            durationMs: 42,
            context: context
        )

        XCTAssertEqual(data["conversationID"], context.conversationID.uuidString)
        XCTAssertEqual(data["threadID"], context.threadID.uuidString)
        XCTAssertEqual(data["providerType"], "anthropic")
        XCTAssertEqual(data["modelID"], "claude-sonnet-test")
        XCTAssertEqual(data["historyCount"], "7")
        XCTAssertEqual(data["toolCount"], "3")
        XCTAssertEqual(data["durationMs"], "42")
    }

    func testUIFlushDiagnosticDataPreservesContextAndDeltaCounts() {
        let context = makeSessionContext(providerType: .openai)
        let flush = StreamingUIFlush(
            textDelta: "hello",
            thinkingDelta: "reasoning",
            isFirstFlush: true,
            force: true
        )

        let firstFlushData = ChatStreamingOrchestrator.firstUIFlushDiagnosticData(
            for: flush,
            context: context
        )
        XCTAssertEqual(firstFlushData["conversationID"], context.conversationID.uuidString)
        XCTAssertEqual(firstFlushData["threadID"], context.threadID.uuidString)
        XCTAssertEqual(firstFlushData["force"], "true")
        XCTAssertEqual(firstFlushData["textDeltaCount"], "5")
        XCTAssertEqual(firstFlushData["thinkingDeltaCount"], "9")

        let deltaData = ChatStreamingOrchestrator.uiFlushDeltaDiagnosticData(
            for: flush,
            context: context
        )
        XCTAssertEqual(deltaData["conversationID"], context.conversationID.uuidString)
        XCTAssertEqual(deltaData["threadID"], context.threadID.uuidString)
        XCTAssertNil(deltaData["force"])
        XCTAssertEqual(deltaData["textDeltaCount"], "5")
        XCTAssertEqual(deltaData["thinkingDeltaCount"], "9")
    }

    @MainActor
    func testApplyStreamingUIFlushAppendsDeltasToStreamingState() async {
        let state = StreamingMessageState()
        let context = makeSessionContext(providerType: .openai)
        let flush = StreamingUIFlush(
            textDelta: "hello",
            thinkingDelta: "reasoning",
            isFirstFlush: true,
            force: false
        )

        await ChatStreamingOrchestrator.applyStreamingUIFlush(
            flush,
            streamingState: state,
            context: context
        )

        XCTAssertEqual(state.textContent, "hello")
        XCTAssertEqual(state.thinkingContent, "reasoning")
        XCTAssertEqual(state.renderTick, 1)
    }

    @MainActor
    func testFlushStreamingUIIfNeededConsumesDueBufferAndSkipsEarlyFlush() async {
        var buffer = StreamingUIFlushBuffer()
        let state = StreamingMessageState()
        let context = makeSessionContext(providerType: .openai)

        buffer.appendText("hello")
        buffer.appendThinking("reasoning")

        await ChatStreamingOrchestrator.flushStreamingUIIfNeeded(
            buffer: &buffer,
            now: 0.01,
            streamingState: state,
            context: context
        )

        XCTAssertEqual(state.textContent, "")
        XCTAssertEqual(state.thinkingContent, "")
        XCTAssertEqual(state.renderTick, 0)

        await ChatStreamingOrchestrator.flushStreamingUIIfNeeded(
            buffer: &buffer,
            now: 0.08,
            streamingState: state,
            context: context
        )

        XCTAssertEqual(state.textContent, "hello")
        XCTAssertEqual(state.thinkingContent, "reasoning")
        XCTAssertEqual(state.renderTick, 1)
        XCTAssertEqual(buffer.lastFlushUptime, 0.08)
    }

    func testApplyStreamContentPartUpdatesAccumulatorBufferAndDiagnostics() throws {
        var accumulator = StreamingResponseAccumulator(providerType: .openai)
        var buffer = StreamingUIFlushBuffer()
        var diagnostics = ChatStreamingOrchestrator.StreamingLoopDiagnosticState()
        let context = makeSessionContext(providerType: .openai)
        let image = ImageContent(mimeType: "image/png", data: Data([1]))
        let video = VideoContent(mimeType: "video/mp4", data: Data([2]))

        ChatStreamingOrchestrator.applyStreamContentPart(
            .text("hello"),
            accumulator: &accumulator,
            uiFlushBuffer: &buffer,
            diagnostics: &diagnostics,
            context: context
        )
        ChatStreamingOrchestrator.applyStreamContentPart(
            .image(image),
            accumulator: &accumulator,
            uiFlushBuffer: &buffer,
            diagnostics: &diagnostics,
            context: context
        )
        ChatStreamingOrchestrator.applyStreamContentPart(
            .video(video),
            accumulator: &accumulator,
            uiFlushBuffer: &buffer,
            diagnostics: &diagnostics,
            context: context
        )

        let flush = try XCTUnwrap(buffer.flushIfNeeded(force: true, now: 0))
        XCTAssertEqual(flush.textDelta, "hello")
        XCTAssertEqual(flush.thinkingDelta, "")
        XCTAssertTrue(diagnostics.didObserveFirstContentDelta)

        let parts = accumulator.snapshot().assistantParts
        XCTAssertEqual(parts.count, 3)
        guard case .text("hello") = parts[0] else {
            return XCTFail("Expected accumulated text part")
        }
        guard case .image(let accumulatedImage) = parts[1] else {
            return XCTFail("Expected accumulated image part")
        }
        XCTAssertEqual(accumulatedImage, image)
        guard case .video(let accumulatedVideo) = parts[2] else {
            return XCTFail("Expected accumulated video part")
        }
        XCTAssertEqual(accumulatedVideo, video)
    }

    func testApplyStreamThinkingDeltaUpdatesAccumulatorBufferAndDiagnostics() throws {
        var accumulator = StreamingResponseAccumulator(providerType: .anthropic)
        var buffer = StreamingUIFlushBuffer()
        var diagnostics = ChatStreamingOrchestrator.StreamingLoopDiagnosticState()
        let context = makeSessionContext(providerType: .anthropic)

        ChatStreamingOrchestrator.applyStreamThinkingDelta(
            .thinking(textDelta: "reasoning", signature: "sig-1"),
            accumulator: &accumulator,
            uiFlushBuffer: &buffer,
            diagnostics: &diagnostics,
            context: context
        )
        ChatStreamingOrchestrator.applyStreamThinkingDelta(
            .thinking(textDelta: "", signature: "sig-2"),
            accumulator: &accumulator,
            uiFlushBuffer: &buffer,
            diagnostics: &diagnostics,
            context: context
        )
        ChatStreamingOrchestrator.applyStreamThinkingDelta(
            .redacted(data: "hidden"),
            accumulator: &accumulator,
            uiFlushBuffer: &buffer,
            diagnostics: &diagnostics,
            context: context
        )

        let flush = try XCTUnwrap(buffer.flushIfNeeded(force: true, now: 0))
        XCTAssertEqual(flush.textDelta, "")
        XCTAssertEqual(flush.thinkingDelta, "reasoning")
        XCTAssertTrue(diagnostics.didObserveFirstThinkingDelta)

        let parts = accumulator.snapshot().assistantParts
        XCTAssertEqual(parts.count, 2)
        guard case .thinking(let thinking) = parts[0] else {
            return XCTFail("Expected accumulated thinking part")
        }
        XCTAssertEqual(thinking.text, "reasoning")
        XCTAssertEqual(thinking.signature, "sig-2")
        XCTAssertEqual(thinking.provider, ProviderType.anthropic.rawValue)
        guard case .redactedThinking(let redacted) = parts[1] else {
            return XCTFail("Expected accumulated redacted thinking part")
        }
        XCTAssertEqual(redacted.data, "hidden")
        XCTAssertEqual(redacted.provider, ProviderType.anthropic.rawValue)
    }

    @MainActor
    func testApplyStreamToolCallUpdatesAccumulatorAndStreamingState() async {
        var accumulator = StreamingResponseAccumulator(providerType: .openai)
        let state = StreamingMessageState()
        let partialCall = ToolCall(
            id: "call-1",
            name: "lookup",
            arguments: ["query": AnyCodable("swift")]
        )
        let completedCall = ToolCall(
            id: "call-1",
            name: "lookup",
            arguments: ["limit": AnyCodable(3)],
            signature: "sig"
        )

        await ChatStreamingOrchestrator.applyStreamToolCall(
            partialCall,
            accumulator: &accumulator,
            streamingState: state
        )
        await ChatStreamingOrchestrator.applyStreamToolCall(
            completedCall,
            accumulator: &accumulator,
            streamingState: state
        )

        XCTAssertEqual(accumulator.buildToolCalls().single?.id, "call-1")
        XCTAssertEqual(accumulator.buildToolCalls().single?.arguments["query"]?.value as? String, "swift")
        XCTAssertEqual(accumulator.buildToolCalls().single?.arguments["limit"]?.value as? Int, 3)
        XCTAssertEqual(accumulator.buildToolCalls().single?.signature, "sig")
        XCTAssertEqual(state.streamingToolCalls.single?.id, "call-1")
        XCTAssertEqual(state.streamingToolCalls.single?.signature, "sig")
    }

    @MainActor
    func testApplyStreamActivitiesUpdateAccumulatorAndStreamingState() async {
        var accumulator = StreamingResponseAccumulator(providerType: .openai)
        let state = StreamingMessageState()
        let searchActivity = SearchActivity(
            id: "search-1",
            type: "web_search",
            status: .searching,
            arguments: ["query": AnyCodable("swift")]
        )
        let codeActivity = CodeExecutionActivity(
            id: "code-1",
            status: .writingCode,
            code: "print(\"hi\")"
        )

        await ChatStreamingOrchestrator.applyStreamSearchActivity(
            searchActivity,
            accumulator: &accumulator,
            streamingState: state
        )
        await ChatStreamingOrchestrator.applyStreamCodeExecutionActivity(
            codeActivity,
            accumulator: &accumulator,
            streamingState: state
        )

        XCTAssertEqual(accumulator.buildSearchActivities().single?.id, "search-1")
        XCTAssertEqual(accumulator.buildSearchActivities().single?.arguments["query"]?.value as? String, "swift")
        XCTAssertEqual(state.searchActivities.single?.id, "search-1")
        XCTAssertEqual(state.searchActivities.single?.arguments["query"]?.value as? String, "swift")

        XCTAssertEqual(accumulator.buildCodeExecutionActivities().single?.id, "code-1")
        XCTAssertEqual(accumulator.buildCodeExecutionActivities().single?.code, "print(\"hi\")")
        XCTAssertEqual(state.codeExecutionActivities.single?.id, "code-1")
        XCTAssertEqual(state.codeExecutionActivities.single?.code, "print(\"hi\")")
    }

    func testRequestControlsApplyClaudeManagedSessionAndToolResultUpdates() {
        var controls = GenerationControls()
        let pending = ClaudeManagedAgentPendingToolResult(
            eventID: "event-1",
            toolCallID: "toolu-1",
            toolName: "workspace_search",
            content: "ok",
            isError: false,
            sessionThreadID: "thread-1"
        )

        controls.applyChatStreamingUpdate(
            .claudeManagedSession(
                ClaudeManagedAgentSessionState(
                    remoteSessionID: "session-1",
                    remoteModelID: "claude-sonnet"
                )
            )
        )
        controls.applyChatStreamingUpdate(.claudeManagedCustomToolResults([pending]))

        XCTAssertEqual(controls.claudeManagedSessionID, "session-1")
        XCTAssertEqual(controls.claudeManagedSessionModelID, "claude-sonnet")
        XCTAssertEqual(controls.claudeManagedPendingCustomToolResults.first?.toolCallID, "toolu-1")
    }

    @MainActor
    func testPersistRequestControlStreamUpdateRoutesEachUpdateToMatchingCallback() async {
        let recorder = ContinuationCallbackRecorder()
        let callbacks = makeContinuationCallbacks(recording: recorder)
        let threadID = UUID()
        let pending = ClaudeManagedAgentPendingToolResult(
            eventID: "event-1",
            toolCallID: "toolu-1",
            toolName: "workspace_search",
            content: "ok",
            isError: false,
            sessionThreadID: "thread-1"
        )

        await ChatStreamingOrchestrator.persistRequestControlStreamUpdate(
            .claudeManagedSession(
                ClaudeManagedAgentSessionState(
                    remoteSessionID: "session-1",
                    remoteModelID: "claude-sonnet"
                )
            ),
            threadID: threadID,
            callbacks: callbacks
        )
        await ChatStreamingOrchestrator.persistRequestControlStreamUpdate(
            .claudeManagedCustomToolResults([pending]),
            threadID: threadID,
            callbacks: callbacks
        )

        XCTAssertEqual(recorder.persistedClaudeManagedSessionState?.remoteSessionID, "session-1")
        XCTAssertEqual(recorder.persistedClaudeManagedSessionState?.remoteModelID, "claude-sonnet")
        XCTAssertEqual(recorder.persistedClaudeManagedSessionLocalThreadID, threadID)
        XCTAssertTrue(recorder.didPersistPendingResults)
        XCTAssertEqual(recorder.persistedPendingResults.single?.toolCallID, "toolu-1")
        XCTAssertEqual(recorder.persistedPendingResultsThreadID, threadID)
    }

    @MainActor
    func testApplyRequestControlStreamUpdatePersistsClaudeManagedPendingResults() async {
        let recorder = ContinuationCallbackRecorder()
        let callbacks = makeContinuationCallbacks(recording: recorder)
        let threadID = UUID()
        var controls = GenerationControls()
        let pending = ClaudeManagedAgentPendingToolResult(
            eventID: "event-1",
            toolCallID: "toolu-1",
            toolName: "workspace_search",
            content: "ok",
            isError: false,
            sessionThreadID: "thread-1"
        )

        await ChatStreamingOrchestrator.applyRequestControlStreamUpdate(
            .claudeManagedCustomToolResults([pending]),
            requestControls: &controls,
            threadID: threadID,
            callbacks: callbacks
        )

        XCTAssertEqual(controls.claudeManagedPendingCustomToolResults.single?.toolCallID, "toolu-1")
        XCTAssertTrue(recorder.didPersistPendingResults)
        XCTAssertEqual(recorder.persistedPendingResults.single?.toolCallID, "toolu-1")
        XCTAssertEqual(recorder.persistedPendingResultsThreadID, threadID)
    }

    func testClaudeManagedPendingToolResultsPreservesProviderContextAndMatchedResultsOnly() {
        let matchedCall = ToolCall(
            id: "event-1",
            name: "session.tool",
            arguments: [:],
            providerContext: [
                "underlying_tool_use_id": "toolu-1",
                "session_thread_id": "managed-thread-1"
            ]
        )
        let unmatchedCall = ToolCall(id: "event-2", name: "ignored", arguments: [:])
        let results = [
            ToolResult(
                toolCallID: "event-1",
                toolName: "reported-name",
                content: "ok",
                isError: false
            )
        ]

        let pending = ChatStreamingOrchestrator.claudeManagedPendingToolResults(
            for: [matchedCall, unmatchedCall],
            toolResults: results
        )

        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.eventID, "event-1")
        XCTAssertEqual(pending.first?.toolCallID, "toolu-1")
        XCTAssertEqual(pending.first?.toolName, "reported-name")
        XCTAssertEqual(pending.first?.content, "ok")
        XCTAssertEqual(pending.first?.isError, false)
        XCTAssertEqual(pending.first?.sessionThreadID, "managed-thread-1")
    }

    func testClaudeManagedPendingToolResultsKeepFirstResultForDuplicateToolCallIDs() {
        let call = ToolCall(id: "event-1", name: "session.tool", arguments: [:])
        let results = [
            ToolResult(toolCallID: "event-1", toolName: "first", content: "first output"),
            ToolResult(toolCallID: "event-1", toolName: "second", content: "second output")
        ]

        let pending = ChatStreamingOrchestrator.claudeManagedPendingToolResults(
            for: [call],
            toolResults: results
        )

        XCTAssertEqual(pending.single?.toolName, "first")
        XCTAssertEqual(pending.single?.content, "first output")
    }

    func testClaudeManagedPendingToolResultFallsBackToEventIDAndToolNameWhenProviderContextIsMissing() {
        let call = ToolCall(id: "event-1", name: "session.tool", arguments: [:])
        let result = ToolResult(toolCallID: "event-1", content: "ok", isError: true)

        let pending = ChatStreamingOrchestrator.claudeManagedPendingToolResult(
            for: call,
            result: result
        )

        XCTAssertEqual(pending.eventID, "event-1")
        XCTAssertEqual(pending.toolCallID, "event-1")
        XCTAssertEqual(pending.toolName, "session.tool")
        XCTAssertEqual(pending.content, "ok")
        XCTAssertEqual(pending.isError, true)
        XCTAssertNil(pending.sessionThreadID)
    }

    func testFollowUpToolMessageCombinesOutputLinesAndOmitsEmptySearchActivities() {
        let toolResult = ToolResult(
            toolCallID: "call-1",
            toolName: "lookup",
            content: "result",
            isError: false
        )
        let message = ChatStreamingOrchestrator.followUpToolMessage(
            from: ChatStreamingOrchestrator.ToolExecutionResult(
                results: [toolResult],
                outputLines: ["first", "second"],
                searchActivities: [],
                cancelled: false
            )
        )

        XCTAssertEqual(message.role, .tool)
        XCTAssertEqual(message.toolResults?.count, 1)
        XCTAssertNil(message.searchActivities)
        XCTAssertEqual(message.content.count, 1)
        guard case .text(let text) = message.content.first else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(text, "first\n\nsecond")
    }

    func testToolOutputLineFormatsSuccessAndFailure() {
        XCTAssertEqual(
            ChatStreamingOrchestrator.toolOutputLine(
                toolName: "lookup",
                content: "found",
                isError: false
            ),
            "Tool lookup:\nfound"
        )
        XCTAssertEqual(
            ChatStreamingOrchestrator.toolOutputLine(
                toolName: "lookup",
                content: "missing",
                isError: true
            ),
            "Tool lookup failed:\nmissing"
        )
        XCTAssertEqual(
            ChatStreamingOrchestrator.deniedToolOutputLine(toolName: "lookup"),
            "Tool lookup denied by user."
        )
    }

    func testToolExecutionRoutePrefersBuiltinThenMCP() async throws {
        let suiteName = "ChatStreamingOrchestratorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: AppPreferenceKeys.pluginWebSearchEnabled)
        defaults.set(SearchPluginProvider.exa.rawValue, forKey: AppPreferenceKeys.pluginWebSearchDefaultProvider)
        defaults.set(8, forKey: AppPreferenceKeys.pluginWebSearchDefaultMaxResults)
        defaults.set("exa-key", forKey: AppPreferenceKeys.pluginWebSearchExaAPIKey)
        let (_, builtinRoutes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: GenerationControls(
                webSearch: WebSearchControls(enabled: true),
                searchPlugin: SearchPluginControls(provider: .exa)
            ),
            useBuiltinSearch: true,
            defaults: defaults
        )

        XCTAssertEqual(
            ChatStreamingOrchestrator.toolExecutionRoute(
                for: ToolCall(id: "builtin", name: BuiltinSearchToolHub.functionName, arguments: [:]),
                builtinRoutes: builtinRoutes
            ),
            .builtin
        )
        XCTAssertEqual(
            ChatStreamingOrchestrator.toolExecutionRoute(
                for: ToolCall(id: "mcp", name: "server__tool", arguments: [:]),
                builtinRoutes: builtinRoutes
            ),
            .mcp
        )
    }

    func testExecutableToolCallsDropsProviderNativeGoogleTools() {
        let toolCalls = [
            ToolCall(id: "call-1", name: "google_search", arguments: [:]),
            ToolCall(id: "call-2", name: "server__lookup", arguments: [:]),
            ToolCall(id: "call-3", name: "google_maps", arguments: [:])
        ]

        let executable = ChatStreamingOrchestrator.executableToolCalls(from: toolCalls)

        XCTAssertEqual(executable.map(\.id), ["call-2"])
    }

    func testToolSearchStartActivityOnlyBuildsForBuiltinRoute() async throws {
        let suiteName = "ChatStreamingOrchestratorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: AppPreferenceKeys.pluginWebSearchEnabled)
        defaults.set(SearchPluginProvider.exa.rawValue, forKey: AppPreferenceKeys.pluginWebSearchDefaultProvider)
        defaults.set(8, forKey: AppPreferenceKeys.pluginWebSearchDefaultMaxResults)
        defaults.set("exa-key", forKey: AppPreferenceKeys.pluginWebSearchExaAPIKey)
        let (_, builtinRoutes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: GenerationControls(
                webSearch: WebSearchControls(enabled: true),
                searchPlugin: SearchPluginControls(provider: .exa)
            ),
            useBuiltinSearch: true,
            defaults: defaults
        )
        let call = ToolCall(
            id: "call-1",
            name: BuiltinSearchToolHub.functionName,
            arguments: ["query": AnyCodable("Swift")]
        )

        let startActivity = ChatStreamingOrchestrator.toolSearchStartActivity(
            for: call,
            builtinRoutes: builtinRoutes
        )

        XCTAssertEqual(startActivity?.id, "tool-search-call-1")
        XCTAssertEqual(startActivity?.status, .searching)
        XCTAssertEqual(startActivity?.arguments["query"]?.value as? String, "Swift")
        XCTAssertEqual(startActivity?.arguments["provider"]?.value as? String, SearchPluginProvider.exa.rawValue)
        XCTAssertNil(
            ChatStreamingOrchestrator.toolSearchStartActivity(
                for: ToolCall(id: "call-2", name: "server__web_search", arguments: ["query": AnyCodable("Swift")]),
                builtinRoutes: builtinRoutes
            )
        )
    }

    func testToolSearchActivityOnlyBuildsForBuiltinRoute() async throws {
        let suiteName = "ChatStreamingOrchestratorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: AppPreferenceKeys.pluginWebSearchEnabled)
        defaults.set(SearchPluginProvider.exa.rawValue, forKey: AppPreferenceKeys.pluginWebSearchDefaultProvider)
        defaults.set(8, forKey: AppPreferenceKeys.pluginWebSearchDefaultMaxResults)
        defaults.set("exa-key", forKey: AppPreferenceKeys.pluginWebSearchExaAPIKey)
        let (_, builtinRoutes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: GenerationControls(
                webSearch: WebSearchControls(enabled: true),
                searchPlugin: SearchPluginControls(provider: .exa)
            ),
            useBuiltinSearch: true,
            defaults: defaults
        )
        let call = ToolCall(
            id: "call-1",
            name: BuiltinSearchToolHub.functionName,
            arguments: ["query": AnyCodable("Swift")]
        )
        let text = """
        [{"title":"Swift","url":"https://swift.org","snippet":"Language"}]
        """

        let builtinActivity = ChatStreamingOrchestrator.toolSearchActivity(
            route: .builtin,
            call: call,
            toolResultText: text,
            isError: false,
            builtinRoutes: builtinRoutes
        )

        XCTAssertEqual(builtinActivity?.id, "tool-search-call-1")
        XCTAssertEqual(builtinActivity?.arguments["provider"]?.value as? String, SearchPluginProvider.exa.rawValue)
        XCTAssertNil(
            ChatStreamingOrchestrator.toolSearchActivity(
                route: .mcp,
                call: call,
                toolResultText: text,
                isError: false,
                builtinRoutes: builtinRoutes
            )
        )
    }

    func testToolResultHelpersPreserveCallMetadataAndNormalizeEmptyOutput() {
        let call = ToolCall(
            id: "call-1",
            name: "lookup",
            arguments: [:],
            signature: "sig"
        )
        let result = MCPToolCallResult(text: "   ", isError: false, rawOutputPath: "/tmp/tool.log")

        let toolResult = ChatStreamingOrchestrator.toolResult(
            for: call,
            result: result,
            durationSeconds: 1.25
        )

        XCTAssertEqual(toolResult.toolCallID, "call-1")
        XCTAssertEqual(toolResult.toolName, "lookup")
        XCTAssertEqual(toolResult.content, "Tool lookup returned no output")
        XCTAssertFalse(toolResult.isError)
        XCTAssertEqual(toolResult.signature, "sig")
        XCTAssertEqual(toolResult.durationSeconds, 1.25)
        XCTAssertEqual(toolResult.rawOutputPath, "/tmp/tool.log")

        let deniedResult = ChatStreamingOrchestrator.toolResult(
            for: call,
            content: ChatStreamingOrchestrator.deniedToolResultContent(),
            isError: true,
            durationSeconds: 0.5
        )
        XCTAssertEqual(
            deniedResult.content,
            "User denied this tool call. Do not retry this exact action without permission."
        )
        XCTAssertTrue(deniedResult.isError)
        XCTAssertEqual(deniedResult.signature, "sig")
    }

    func testToolExecutionProgressPreservesResultOrderAndMergesSearchActivities() {
        var progress = ChatStreamingOrchestrator.ToolExecutionProgress()
        let firstResult = ToolResult(
            toolCallID: "call-1",
            toolName: "search",
            content: "first",
            isError: false
        )
        let secondResult = ToolResult(
            toolCallID: "call-2",
            toolName: "search",
            content: "second",
            isError: false
        )
        let searchingActivity = SearchActivity(
            id: "search-1",
            type: "web_search",
            status: .searching,
            arguments: ["query": AnyCodable("Swift")]
        )
        let completedActivity = SearchActivity(
            id: "search-1",
            type: "web_search",
            status: .completed,
            arguments: ["provider": AnyCodable("exa")]
        )

        progress.appendResult(firstResult, outputLine: "first line")
        progress.upsertSearchActivity(searchingActivity)
        progress.appendResult(secondResult, outputLine: "second line")
        progress.upsertSearchActivity(completedActivity)

        let result = progress.result(cancelled: false)

        XCTAssertEqual(result.results.map(\.toolCallID), ["call-1", "call-2"])
        XCTAssertEqual(result.outputLines, ["first line", "second line"])
        XCTAssertEqual(result.searchActivities.single?.id, "search-1")
        XCTAssertEqual(result.searchActivities.single?.status, .completed)
        XCTAssertEqual(result.searchActivities.single?.arguments["query"]?.value as? String, "Swift")
        XCTAssertEqual(result.searchActivities.single?.arguments["provider"]?.value as? String, "exa")
        XCTAssertFalse(result.cancelled)
    }

    func testToolExecutionFailureContentNormalizesEmptyError() {
        struct EmptyLocalizedError: LocalizedError {
            var errorDescription: String? { "" }
        }
        let call = ToolCall(id: "call-1", name: "lookup", arguments: [:])

        let content = ChatStreamingOrchestrator.toolExecutionFailureContent(
            for: call,
            error: EmptyLocalizedError()
        )

        XCTAssertEqual(
            content,
            "Tool execution failed: Tool lookup failed without details. You may retry this tool call with corrected arguments."
        )
    }

    @MainActor
    func testApplyToolResultOnlyPublishesForVisibleToolCalls() async {
        let state = StreamingMessageState()
        state.setToolCalls([ToolCall(id: "call-1", name: "lookup", arguments: [:])])
        let visibleResult = ToolResult(
            toolCallID: "call-1",
            toolName: "lookup",
            content: "ok",
            isError: false
        )
        let hiddenResult = ToolResult(
            toolCallID: "call-2",
            toolName: "lookup",
            content: "ignored",
            isError: false
        )

        await ChatStreamingOrchestrator.applyToolResult(
            visibleResult,
            streamingState: state
        )
        await ChatStreamingOrchestrator.applyToolResult(
            hiddenResult,
            streamingState: state
        )

        XCTAssertEqual(state.toolResultsByCallID["call-1"]?.content, "ok")
        XCTAssertNil(state.toolResultsByCallID["call-2"])
    }

    @MainActor
    func testPersistToolContinuationPersistsFollowUpAndMergesActivities() async {
        let threadID = UUID()
        let turnID = UUID()
        let assistantMessageID = UUID()
        let recorder = ContinuationCallbackRecorder()
        let matchedCall = ToolCall(
            id: "event-1",
            name: "session.tool",
            arguments: [:],
            providerContext: [
                "underlying_tool_use_id": "toolu-1",
                "session_thread_id": "managed-thread-1"
            ]
        )
        let toolResult = ToolResult(
            toolCallID: "event-1",
            toolName: "reported-name",
            content: "ok",
            isError: false
        )
        let searchActivity = SearchActivity(id: "search-1", type: "web_search", status: .completed)
        let context = makeSessionContext(providerType: .claudeManagedAgents, threadID: threadID, turnID: turnID)
        let callbacks = makeContinuationCallbacks(recording: recorder)

        let result = await ChatStreamingOrchestrator.persistToolContinuation(
            executableToolCalls: [matchedCall],
            toolExecutionResult: ChatStreamingOrchestrator.ToolExecutionResult(
                results: [toolResult],
                outputLines: ["Tool session.tool:\nok"],
                searchActivities: [searchActivity],
                cancelled: false
            ),
            persistedAssistantMessageID: assistantMessageID,
            providerType: .claudeManagedAgents,
            context: context,
            callbacks: callbacks
        )

        XCTAssertEqual(result.toolMessage.role, .tool)
        XCTAssertEqual(result.toolMessage.toolResults?.first?.toolCallID, "event-1")
        XCTAssertEqual(result.toolMessage.searchActivities?.first?.id, "search-1")
        XCTAssertEqual(result.claudeManagedToolResultsForNextRequest.first?.toolCallID, "toolu-1")
        XCTAssertTrue(recorder.didPersistPendingResults)
        XCTAssertEqual(recorder.persistedPendingResults.first?.sessionThreadID, "managed-thread-1")
        XCTAssertEqual(recorder.persistedToolMessage?.id, result.toolMessage.id)
        XCTAssertEqual(recorder.persistedToolThreadID, threadID)
        XCTAssertEqual(recorder.persistedToolTurnID, turnID)
        XCTAssertEqual(recorder.mergedSearchActivities?.messageID, assistantMessageID)
        XCTAssertEqual(recorder.mergedSearchActivities?.activities.first?.id, "search-1")
    }

    @MainActor
    func testPersistToolContinuationDoesNotPersistClaudePendingResultsForOtherProviders() async {
        let recorder = ContinuationCallbackRecorder()
        let context = makeSessionContext(providerType: .openai)
        let callbacks = makeContinuationCallbacks(recording: recorder)

        let result = await ChatStreamingOrchestrator.persistToolContinuation(
            executableToolCalls: [ToolCall(id: "event-1", name: "session.tool", arguments: [:])],
            toolExecutionResult: ChatStreamingOrchestrator.ToolExecutionResult(
                results: [ToolResult(toolCallID: "event-1", toolName: "session.tool", content: "ok")],
                outputLines: ["Tool session.tool:\nok"],
                searchActivities: [],
                cancelled: false
            ),
            persistedAssistantMessageID: nil,
            providerType: .openai,
            context: context,
            callbacks: callbacks
        )

        XCTAssertTrue(result.claudeManagedToolResultsForNextRequest.isEmpty)
        XCTAssertFalse(recorder.didPersistPendingResults)
        XCTAssertNotNil(recorder.persistedToolMessage)
    }

    func testApplyToolContinuationFollowUpAppendsHistoryAndSeedsClaudeManagedPendingResults() {
        var controls = GenerationControls()
        let existingMessage = Message(role: .user, content: [.text("Use a tool")])
        let toolMessage = Message(role: .tool, content: [.text("Tool output")])
        let pending = ClaudeManagedAgentPendingToolResult(
            eventID: "event-1",
            toolCallID: "toolu-1",
            toolName: "workspace_search",
            content: "ok",
            isError: false,
            sessionThreadID: "thread-1"
        )

        let updatedHistory = ChatStreamingOrchestrator.applyToolContinuationFollowUp(
            ChatStreamingOrchestrator.ToolContinuationPersistenceResult(
                toolMessage: toolMessage,
                claudeManagedToolResultsForNextRequest: [pending]
            ),
            providerType: .claudeManagedAgents,
            requestControls: &controls,
            history: [existingMessage]
        )

        XCTAssertEqual(updatedHistory.map(\.id), [existingMessage.id, toolMessage.id])
        XCTAssertEqual(controls.claudeManagedPendingCustomToolResults.single?.toolCallID, "toolu-1")
    }

    func testApplyToolContinuationFollowUpDoesNotSeedClaudeManagedPendingResultsForOtherProviders() {
        var controls = GenerationControls()
        let toolMessage = Message(role: .tool, content: [.text("Tool output")])
        let pending = ClaudeManagedAgentPendingToolResult(
            eventID: "event-1",
            toolCallID: "toolu-1",
            toolName: "workspace_search",
            content: "ok",
            isError: false,
            sessionThreadID: "thread-1"
        )

        let updatedHistory = ChatStreamingOrchestrator.applyToolContinuationFollowUp(
            ChatStreamingOrchestrator.ToolContinuationPersistenceResult(
                toolMessage: toolMessage,
                claudeManagedToolResultsForNextRequest: [pending]
            ),
            providerType: .openai,
            requestControls: &controls,
            history: []
        )

        XCTAssertEqual(updatedHistory.single?.id, toolMessage.id)
        XCTAssertTrue(controls.claudeManagedPendingCustomToolResults.isEmpty)
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
