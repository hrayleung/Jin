import SwiftUI
import SwiftData
import AppKit

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var conversationEntity: ConversationEntity
    let onRequestDeleteConversation: () -> Void
    @Query private var providers: [ProviderConfigEntity]
    @Query private var mcpServers: [MCPServerConfigEntity]

    @State private var controls: GenerationControls = GenerationControls()
    @State private var messageText = ""
    @State private var isStreaming = false
    @State private var streamingMessage: StreamingMessageState?
    @State private var streamingTask: Task<Void, Never>?

    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingThinkingBudgetSheet = false
    @State private var thinkingBudgetDraft = ""
    @State private var maxTokensDraft = ""

    private var orderedMessages: [MessageEntity] {
        conversationEntity.messages.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        let bubbleMaxWidth = maxBubbleWidth(for: geometry.size.width)
                        LazyVStack(alignment: .leading, spacing: 0) { // Zero spacing, controlled by padding in rows
                            ForEach(orderedMessages) { message in
                                MessageRow(messageEntity: message, maxBubbleWidth: bubbleMaxWidth)
                                    .id(message.id)
                            }

                            // Streaming message
                            if let streaming = streamingMessage {
                                StreamingMessageView(state: streaming, maxBubbleWidth: bubbleMaxWidth)
                                    .id("streaming")
                            }
                            
                            Spacer(minLength: 20)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical)
                    }
                    .onChange(of: conversationEntity.messages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: streamingMessage) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }
            }

            Divider()

            // Desktop-class Composer
            VStack(spacing: 8) {
                if !messageText.isEmpty {
                    HStack {
                        Spacer()
                        Text("\(messageText.count) chars")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
                
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack(alignment: .topLeading) {
                            if messageText.isEmpty {
                                Text("Type a message...")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $messageText)
                                .font(.body)
                                .frame(minHeight: 40, maxHeight: 160)
                                .scrollContentBackground(.hidden) // Remove default background
                                .background(Color.clear)
                        }

                        Divider()
                            .padding(.horizontal, 2)

                        HStack(spacing: 6) {
                            Button {} label: {
                                controlIconLabel(systemName: "paperclip", isActive: false, badgeText: nil)
                            }
                            .buttonStyle(.plain)
                            .help("Attach file")

                            Menu {
                                reasoningMenuContent
                            } label: {
                                controlIconLabel(
                                    systemName: "brain",
                                    isActive: isReasoningEnabled,
                                    badgeText: reasoningBadgeText
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .disabled(!supportsReasoningControl)
                            .help(reasoningHelpText)

                            Menu {
                                webSearchMenuContent
                            } label: {
                                controlIconLabel(
                                    systemName: "globe",
                                    isActive: isWebSearchEnabled,
                                    badgeText: webSearchBadgeText
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .disabled(!supportsWebSearchControl)
                            .help(webSearchHelpText)

                            Menu {
                                mcpToolsMenuContent
                            } label: {
                                controlIconLabel(
                                    systemName: "hammer",
                                    isActive: supportsMCPToolsControl && isMCPToolsEnabled,
                                    badgeText: mcpToolsBadgeText
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .disabled(!supportsMCPToolsControl)
                            .help(mcpToolsHelpText)

                            Spacer(minLength: 0)
                        }
                        .padding(.bottom, 2)
                    }
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                    Button(action: sendMessage) {
                        Image(systemName: isStreaming ? "stop.fill" : "arrow.up.circle.fill")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(isStreaming ? .red : (messageText.isEmpty ? .gray : Color.accentColor))
                    }
                    .buttonStyle(.plain)
                    .disabled(messageText.isEmpty && !isStreaming)
                    .padding(.bottom, 4)
                }
                .padding(12)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .background(Color(nsColor: .textBackgroundColor)) // Main chat background
        .navigationTitle(conversationEntity.title)
        .navigationSubtitle(currentModelName)
        .toolbar {
            ToolbarItemGroup {
                modelPickerMenu

                Button(role: .destructive) {
                    onRequestDeleteConversation()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete chat")
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
        .sheet(isPresented: $showingThinkingBudgetSheet) {
            NavigationStack {
                Form {
                    Section("Claude thinking") {
                        Text("Use token budgets to control extended thinking and tool interleaving.")
                            .foregroundStyle(.secondary)

                        TextField("Thinking budget tokens", text: $thinkingBudgetDraft)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)

                        TextField("Max tokens (optional)", text: $maxTokensDraft)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)

                        if let warning = thinkingBudgetValidationWarning {
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Thinking")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingThinkingBudgetSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            applyThinkingBudgetDraft()
                            showingThinkingBudgetSheet = false
                        }
                        .disabled(thinkingBudgetDraftInt == nil)
                    }
                }
            }
            .frame(width: 420)
        }
        .task {
            loadControlsFromConversation()
        }
    }
    
    // MARK: - Helpers & Subviews
    
    private var selectedModelInfo: ModelInfo? {
        availableModels.first(where: { $0.id == conversationEntity.modelID })
    }

    private var selectedReasoningConfig: ModelReasoningConfig? {
        selectedModelInfo?.reasoningConfig
    }

    private var isReasoningEnabled: Bool {
        controls.reasoning?.enabled == true
    }

    private var isWebSearchEnabled: Bool {
        controls.webSearch?.enabled == true
    }

    private var isMCPToolsEnabled: Bool {
        controls.mcpTools?.enabled ?? true
    }

    private var supportsReasoningControl: Bool {
        guard let config = selectedReasoningConfig else { return false }
        return config.type != .none
    }

    private var supportsWebSearchControl: Bool {
        // Provider-native web search, not MCP. Today: OpenAI, Anthropic, xAI, Vertex AI.
        switch providerType {
        case .openai, .anthropic, .xai, .vertexai:
            return true
        case .none:
            return false
        }
    }

    private var supportsMCPToolsControl: Bool {
        selectedModelInfo?.capabilities.contains(.toolCalling) == true
    }

    private var reasoningHelpText: String {
        guard supportsReasoningControl else { return "Reasoning: Not supported" }
        switch providerType {
        case .anthropic, .vertexai:
            return "Thinking: \(reasoningLabel)"
        case .openai, .xai, .none:
            return "Reasoning: \(reasoningLabel)"
        }
    }

    private var webSearchHelpText: String {
        guard supportsWebSearchControl else { return "Web Search: Not supported" }
        guard isWebSearchEnabled else { return "Web Search: Off" }
        return "Web Search: \(webSearchLabel)"
    }

    private var mcpToolsHelpText: String {
        guard supportsMCPToolsControl else { return "MCP Tools: Not supported" }
        guard isMCPToolsEnabled else { return "MCP Tools: Off" }
        let count = selectedMCPServerIDs.count
        if count == 0 { return "MCP Tools: On (no servers)" }
        return "MCP Tools: On (\(count) server\(count == 1 ? "" : "s"))"
    }

    private var webSearchLabel: String {
        switch providerType {
        case .openai:
            return (controls.webSearch?.contextSize ?? .medium).displayName
        case .xai:
            return webSearchSourcesLabel
        case .anthropic, .vertexai, .none:
            return "On"
        }
    }

    private var webSearchSourcesLabel: String {
        let sources = Set(controls.webSearch?.sources ?? [])
        if sources.isEmpty { return "On" }
        if sources == [.web] { return "Web" }
        if sources == [.x] { return "X" }
        return "Web + X"
    }

    private var reasoningBadgeText: String? {
        guard supportsReasoningControl, isReasoningEnabled else { return nil }

        guard let reasoningType = selectedReasoningConfig?.type, reasoningType != .none else { return nil }

        switch reasoningType {
        case .budget:
            switch controls.reasoning?.budgetTokens {
            case 1024: return "L"
            case 2048: return "M"
            case 4096: return "H"
            case 8192: return "X"
            default: return "On"
            }
        case .effort:
            guard let effort = controls.reasoning?.effort else { return "On" }
            switch effort {
            case .none: return nil
            case .minimal: return "Min"
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            case .xhigh: return "X"
            }
        case .none:
            return nil
        }
    }

    private var webSearchBadgeText: String? {
        guard supportsWebSearchControl, isWebSearchEnabled else { return nil }

        switch providerType {
        case .openai:
            switch controls.webSearch?.contextSize ?? .medium {
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            }
        case .xai:
            let sources = Set(controls.webSearch?.sources ?? [])
            if sources == [.web] { return "W" }
            if sources == [.x] { return "X" }
            if sources.contains(.web), sources.contains(.x) { return "WX" }
            return "On"
        case .anthropic, .vertexai, .none:
            return "On"
        }
    }

    private var mcpToolsBadgeText: String? {
        guard supportsMCPToolsControl, isMCPToolsEnabled else { return nil }
        let count = selectedMCPServerIDs.count
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }

    private var eligibleMCPServers: [MCPServerConfigEntity] {
        mcpServers
            .filter { $0.isEnabled && $0.runToolsAutomatically }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var selectedMCPServerIDs: Set<String> {
        let eligibleIDs = Set(eligibleMCPServers.map(\.id))
        if let allowlist = controls.mcpTools?.enabledServerIDs {
            return Set(allowlist).intersection(eligibleIDs)
        }
        return eligibleIDs
    }

    @ViewBuilder
    private func controlIconLabel(systemName: String, isActive: Bool, badgeText: String?) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isActive ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                )

            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .foregroundStyle(.primary)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .offset(x: 4, y: 4)
            }
        }
    }

    private var modelPickerMenu: some View {
        Menu {
            Section("Provider") {
                ForEach(providers) { provider in
                    Button {
                        setProvider(provider.id)
                    } label: {
                        HStack {
                            Text(provider.name)
                            if provider.id == conversationEntity.providerID {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section("Model") {
                if availableModels.isEmpty {
                    Text("No models configured.")
                } else {
                    ForEach(availableModels) { model in
                        Button {
                            setModel(model.id)
                        } label: {
                            HStack {
                                Text(model.name)
                                if model.id == conversationEntity.modelID {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentModelName)
                    .font(.callout)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var currentModelName: String {
        availableModels.first(where: { $0.id == conversationEntity.modelID })?.name ?? conversationEntity.modelID
    }

    private var availableModels: [ModelInfo] {
        guard let provider = providers.first(where: { $0.id == conversationEntity.providerID }),
              let models = try? JSONDecoder().decode([ModelInfo].self, from: provider.modelsData) else {
            return []
        }
        return models
    }

    private func setProvider(_ providerID: String) {
        guard providerID != conversationEntity.providerID else { return }

        conversationEntity.providerID = providerID
        conversationEntity.updatedAt = Date()

        let models = availableModels
        if let preferredModelID = preferredModelID(in: models, providerID: providerID) {
            conversationEntity.modelID = preferredModelID
            normalizeControlsForCurrentSelection()
            return
        }
        conversationEntity.modelID = models.first?.id ?? conversationEntity.modelID
        normalizeControlsForCurrentSelection()
    }

    private func setModel(_ modelID: String) {
        guard modelID != conversationEntity.modelID else { return }
        conversationEntity.modelID = modelID
        conversationEntity.updatedAt = Date()
        normalizeControlsForCurrentSelection()
    }

    private func preferredModelID(in models: [ModelInfo], providerID: String) -> String? {
        guard let provider = providers.first(where: { $0.id == providerID }),
              let type = ProviderType(rawValue: provider.typeRaw) else {
            return nil
        }

        switch type {
        case .openai:
            return models.first(where: { $0.id == "gpt-5.2" })?.id
        case .anthropic:
            return models.first(where: { $0.id == "claude-sonnet-4-5-20250929" })?.id
        case .xai, .vertexai:
            return nil
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = orderedMessages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        } else if streamingMessage != nil {
            proxy.scrollTo("streaming", anchor: .bottom)
        }
    }

    private func maxBubbleWidth(for containerWidth: CGFloat) -> CGFloat {
        let usable = max(0, containerWidth - 32) // Message rows add horizontal padding
        return max(260, usable * 0.78)
    }

    private func resolvedSystemPrompt(conversationSystemPrompt: String?, assistant: AssistantEntity?) -> String? {
        let conversationPrompt = conversationSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantPrompt = assistant?.systemInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyLanguage = assistant?.replyLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)

        var prompt = conversationPrompt
        if prompt?.isEmpty != false {
            prompt = assistantPrompt
        }

        if let replyLanguage, !replyLanguage.isEmpty {
            if prompt?.isEmpty != false {
                prompt = "Always reply in \(replyLanguage)."
            } else {
                prompt = "\(prompt!)\n\nAlways reply in \(replyLanguage)."
            }
        }

        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func truncatedHistory(_ history: [Message], contextWindow: Int, reservedOutputTokens: Int) -> [Message] {
        guard contextWindow > 0 else { return history }

        let effectiveReserved = min(max(0, reservedOutputTokens), contextWindow)
        let budget = max(0, contextWindow - effectiveReserved)

        guard history.count > 2 else { return history }

        var prefix: [Message] = []
        var index = 0
        while index < history.count, history[index].role == .system {
            prefix.append(history[index])
            index += 1
        }

        var totalTokens = prefix.reduce(0) { $0 + approximateTokenCount(for: $1) }
        var tail: [Message] = []

        for message in history[index...].reversed() {
            let tokens = approximateTokenCount(for: message)
            if totalTokens + tokens <= budget || tail.isEmpty {
                tail.append(message)
                totalTokens += tokens
                continue
            }
            break
        }

        return prefix + tail.reversed()
    }

    private func approximateTokenCount(for message: Message) -> Int {
        var tokens = 4 // role/metadata overhead

        for part in message.content {
            tokens += approximateTokenCount(for: part)
        }

        if let toolCalls = message.toolCalls {
            for call in toolCalls {
                tokens += approximateTokenCount(for: call.name)
                for (key, value) in call.arguments {
                    tokens += approximateTokenCount(for: key)
                    tokens += approximateTokenCount(for: String(describing: value.value))
                }
                if let signature = call.signature {
                    tokens += approximateTokenCount(for: signature)
                }
            }
        }

        if let toolResults = message.toolResults {
            for result in toolResults {
                if let toolName = result.toolName {
                    tokens += approximateTokenCount(for: toolName)
                }
                tokens += approximateTokenCount(for: result.content)
                if let signature = result.signature {
                    tokens += approximateTokenCount(for: signature)
                }
            }
        }

        return tokens
    }

    private func approximateTokenCount(for part: ContentPart) -> Int {
        switch part {
        case .text(let text):
            return approximateTokenCount(for: text)
        case .thinking(let thinking):
            return approximateTokenCount(for: thinking.text)
        case .redactedThinking:
            return 16
        case .image(let image):
            if image.data != nil { return 1024 }
            if image.url != nil { return 256 }
            return 256
        case .file(let file):
            return approximateTokenCount(for: file.filename) + 256
        case .audio:
            return 1024
        }
    }

    private func approximateTokenCount(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return max(1, trimmed.count / 4)
    }

    private func sendMessage() {
        if isStreaming {
            streamingTask?.cancel()
            return
        }

        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let message = Message(
            role: .user,
            content: [.text(trimmed)]
        )

        do {
            let messageEntity = try MessageEntity.fromDomain(message)
            messageEntity.conversation = conversationEntity
            conversationEntity.messages.append(messageEntity)
            if conversationEntity.title == "New Chat" {
                conversationEntity.title = makeConversationTitle(from: trimmed)
            }
            conversationEntity.updatedAt = Date()
            messageText = ""
        } catch {
            print("Failed to create message: \(error)")
        }

        startStreamingResponse()
    }

    private func makeConversationTitle(from userText: String) -> String {
        let firstLine = userText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Chat" }
        return String(trimmed.prefix(48))
    }
    
    // ... (Keep existing streaming logic methods here for brevity, assuming no changes needed to logic)
    // For completeness, I should include the streaming logic or the file will break.
    // I will re-paste the streaming logic from the original file.

    private func startStreamingResponse() {
        guard streamingTask == nil else { return }

        let streamingState = StreamingMessageState()
        streamingMessage = streamingState
        isStreaming = true

        let providerConfig = providers.first(where: { $0.id == conversationEntity.providerID }).flatMap { try? $0.toDomain() }
        let baseHistory = conversationEntity.messages
            .sorted(by: { $0.timestamp < $1.timestamp })
            .compactMap { try? $0.toDomain() }
        let assistant = conversationEntity.assistant
        let systemPrompt = resolvedSystemPrompt(
            conversationSystemPrompt: conversationEntity.systemPrompt,
            assistant: assistant
        )
        var controlsToUse: GenerationControls = (try? JSONDecoder().decode(GenerationControls.self, from: conversationEntity.modelConfigData))
            ?? controls
        if let assistant {
            controlsToUse.temperature = assistant.temperature
            if let maxOutputTokens = assistant.maxOutputTokens {
                controlsToUse.maxTokens = maxOutputTokens
            }
        }

        let shouldTruncateMessages = assistant?.truncateMessages ?? false
        let modelContextWindow = selectedModelInfo?.contextWindow ?? 128000
        let reservedOutputTokens = max(0, controlsToUse.maxTokens ?? 2048)
        let mcpServerConfigs = resolvedMCPServerConfigs(for: controlsToUse)
        let modelID = conversationEntity.modelID

        streamingTask = Task {
            do {
                guard let providerConfig else {
                    throw LLMError.invalidRequest(message: "Provider not found. Configure it in Settings.")
                }

                var history = baseHistory
                if let systemPrompt, !systemPrompt.isEmpty {
                    history.insert(Message(role: .system, content: [.text(systemPrompt)]), at: 0)
                }
                if shouldTruncateMessages {
                    history = truncatedHistory(
                        history,
                        contextWindow: modelContextWindow,
                        reservedOutputTokens: reservedOutputTokens
                    )
                }

                let providerManager = ProviderManager()
                let adapter = try await providerManager.createAdapter(for: providerConfig)
                let mcpTools = try await MCPHub.shared.toolDefinitions(for: mcpServerConfigs)

                var iteration = 0
                let maxToolIterations = 8

                while iteration < maxToolIterations {
                    try Task.checkCancellation()

                    var assistantParts: [ContentPart] = []
                    var assistantText = ""
                    var assistantThinkingText = ""
                    var toolCallsByID: [String: ToolCall] = [:]

                    await MainActor.run {
                        streamingState.textContent = ""
                        streamingState.thinkingContent = ""
                    }

                    let stream = try await adapter.sendMessage(
                        messages: history,
                        modelID: modelID,
                        controls: controlsToUse,
                        tools: mcpTools,
                        streaming: true
                    )

                    for try await event in stream {
                        try Task.checkCancellation()

                        switch event {
                        case .messageStart: break
                        case .contentDelta(let part):
                            if case .text(let delta) = part {
                                assistantText += delta
                                appendTextDelta(delta, to: &assistantParts)
                                await MainActor.run { streamingState.textContent = assistantText }
                            }
                        case .thinkingDelta(let delta):
                            appendThinkingDelta(delta, to: &assistantParts)
                            switch delta {
                            case .thinking(let textDelta, _):
                                if !textDelta.isEmpty { assistantThinkingText += textDelta }
                            case .redacted:
                                assistantThinkingText = assistantThinkingText.isEmpty ? "Thinking (redacted)" : assistantThinkingText
                            }
                            await MainActor.run { streamingState.thinkingContent = assistantThinkingText }
                        case .toolCallStart(let call): toolCallsByID[call.id] = call
                        case .toolCallDelta: break
                        case .toolCallEnd(let call): toolCallsByID[call.id] = call
                        case .messageEnd: break
                        case .error(let err): throw err
                        }
                    }

                    let toolCalls = Array(toolCallsByID.values)
                    await MainActor.run {
                        if !assistantParts.isEmpty || !toolCalls.isEmpty {
                            let assistantMessage = Message(role: .assistant, content: assistantParts, toolCalls: toolCalls.isEmpty ? nil : toolCalls)
                            do {
                                let entity = try MessageEntity.fromDomain(assistantMessage)
                                entity.conversation = conversationEntity
                                conversationEntity.messages.append(entity)
                                conversationEntity.updatedAt = Date()
                            } catch {
                                errorMessage = error.localizedDescription
                                showingError = true
                            }
                            history.append(assistantMessage)
                        }
                    }

                    guard !toolCalls.isEmpty else { break }

                    await MainActor.run {
                        streamingState.textContent = "Running tools…"
                        streamingState.thinkingContent = ""
                    }

                    var toolResults: [ToolResult] = []
                    var toolOutputLines: [String] = []

                    for call in toolCalls {
                        do {
                            let result = try await MCPHub.shared.executeTool(functionName: call.name, arguments: call.arguments)
                            toolResults.append(ToolResult(toolCallID: call.id, toolName: call.name, content: result.text, isError: result.isError, signature: call.signature))
                            toolOutputLines.append("Tool \(call.name):\n\(result.text)")
                        } catch {
                            toolResults.append(ToolResult(toolCallID: call.id, toolName: call.name, content: error.localizedDescription, isError: true, signature: call.signature))
                            toolOutputLines.append("Tool \(call.name) failed:\n\(error.localizedDescription)")
                        }
                    }

                    let toolMessage = Message(role: .tool, content: toolOutputLines.isEmpty ? [] : [.text(toolOutputLines.joined(separator: "\n\n"))], toolResults: toolResults)
                    await MainActor.run {
                        do {
                            let entity = try MessageEntity.fromDomain(toolMessage)
                            entity.conversation = conversationEntity
                            conversationEntity.messages.append(entity)
                            conversationEntity.updatedAt = Date()
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                    history.append(toolMessage)
                    iteration += 1
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            await MainActor.run {
                isStreaming = false
                streamingMessage = nil
                streamingTask = nil
            }
        }
    }

    private func appendTextDelta(_ delta: String, to parts: inout [ContentPart]) {
        if case .text(let existing) = parts.last {
            parts[parts.count - 1] = .text(existing + delta)
        } else {
            parts.append(.text(delta))
        }
    }

    private func appendThinkingDelta(_ delta: ThinkingDelta, to parts: inout [ContentPart]) {
        switch delta {
        case .thinking(let textDelta, let signature):
            if textDelta.isEmpty, let signature, case .thinking(let existing) = parts.last, existing.signature == nil {
                parts[parts.count - 1] = .thinking(ThinkingBlock(text: existing.text, signature: signature))
                return
            }
            if case .thinking(let existing) = parts.last, existing.signature == signature {
                if !textDelta.isEmpty {
                    parts[parts.count - 1] = .thinking(ThinkingBlock(text: existing.text + textDelta, signature: existing.signature))
                }
            } else {
                parts.append(.thinking(ThinkingBlock(text: textDelta, signature: signature)))
            }
        case .redacted(let data):
            parts.append(.redactedThinking(RedactedThinkingBlock(data: data)))
        }
    }
    
    // MARK: - Model Controls (Shortened for brevity, preserving existing logic)
    
    private var providerType: ProviderType? {
        guard let provider = providers.first(where: { $0.id == conversationEntity.providerID }) else { return nil }
        return ProviderType(rawValue: provider.typeRaw)
    }

    private var reasoningLabel: String {
        guard supportsReasoningControl else { return "Not supported" }
        guard isReasoningEnabled else { return "Off" }

        guard let reasoningType = selectedReasoningConfig?.type, reasoningType != .none else { return "Not supported" }

        switch reasoningType {
        case .budget:
            guard let budgetTokens = controls.reasoning?.budgetTokens else { return "On" }
            switch budgetTokens {
            case 1024: return "Low"
            case 2048: return "Medium"
            case 4096: return "High"
            case 8192: return "Extreme"
            default: return "\(budgetTokens) tokens"
            }
        case .effort:
            return controls.reasoning?.effort?.displayName ?? "On"
        case .none:
            return "Not supported"
        }
    }

    @ViewBuilder
    private var reasoningMenuContent: some View {
        if let reasoningConfig = selectedReasoningConfig, reasoningConfig.type != .none {
            Button { setReasoningOff() } label: { menuItemLabel("Off", isSelected: !isReasoningEnabled) }

            switch reasoningConfig.type {
            case .effort:
                switch providerType {
                case .vertexai:
                    Button { setReasoningEffort(.minimal) } label: { menuItemLabel("Minimal", isSelected: isReasoningEnabled && controls.reasoning?.effort == .minimal) }
                    Button { setReasoningEffort(.low) } label: { menuItemLabel("Low", isSelected: isReasoningEnabled && controls.reasoning?.effort == .low) }
                    Button { setReasoningEffort(.medium) } label: { menuItemLabel("Medium", isSelected: isReasoningEnabled && controls.reasoning?.effort == .medium) }
                    Button { setReasoningEffort(.high) } label: { menuItemLabel("High", isSelected: isReasoningEnabled && controls.reasoning?.effort == .high) }

                case .openai:
                    Button { setReasoningEffort(.low) } label: { menuItemLabel("Low", isSelected: isReasoningEnabled && controls.reasoning?.effort == .low) }
                    Button { setReasoningEffort(.medium) } label: { menuItemLabel("Medium", isSelected: isReasoningEnabled && controls.reasoning?.effort == .medium) }
                    Button { setReasoningEffort(.high) } label: { menuItemLabel("High", isSelected: isReasoningEnabled && controls.reasoning?.effort == .high) }
                    if isOpenAIGPT52SeriesModel {
                        Button { setReasoningEffort(.xhigh) } label: { menuItemLabel("Extreme", isSelected: isReasoningEnabled && controls.reasoning?.effort == .xhigh) }
                    }

                    Divider()
                    Text("Reasoning summary")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(ReasoningSummary.allCases, id: \.self) { summary in
                        Button {
                            setReasoningSummary(summary)
                        } label: {
                            menuItemLabel(summary.displayName, isSelected: (controls.reasoning?.summary ?? .auto) == summary)
                        }
                    }

                case .anthropic, .xai, .none:
                    EmptyView()
                }

            case .budget:
                Button { openThinkingBudgetEditor() } label: {
                    let current = controls.reasoning?.budgetTokens ?? reasoningConfig.defaultBudget ?? 2048
                    menuItemLabel("Budget tokens… (\(current))", isSelected: isReasoningEnabled)
                }

            case .none:
                EmptyView()
            }
        } else {
            Text("Not supported")
                .foregroundStyle(.secondary)
        }
    }

    private func menuItemLabel(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var webSearchEnabledBinding: Binding<Bool> {
        Binding(
            get: { controls.webSearch?.enabled ?? false },
            set: { enabled in
                if controls.webSearch == nil {
                    controls.webSearch = defaultWebSearchControls(enabled: enabled)
                } else {
                    controls.webSearch?.enabled = enabled
                    ensureValidWebSearchDefaultsIfEnabled()
                }
                persistControlsToConversation()
            }
        )
    }

    @ViewBuilder
    private var webSearchMenuContent: some View {
        Toggle("Web Search", isOn: webSearchEnabledBinding)
        if controls.webSearch?.enabled == true {
            switch providerType {
            case .openai:
                Divider()
                ForEach(WebSearchContextSize.allCases, id: \.self) { size in
                    Button {
                        controls.webSearch?.contextSize = size
                        persistControlsToConversation()
                    } label: {
                        menuItemLabel(size.displayName, isSelected: (controls.webSearch?.contextSize ?? .medium) == size)
                    }
                }
            case .xai:
                Divider()
                Toggle("Web", isOn: webSearchSourceBinding(.web))
                Toggle("X", isOn: webSearchSourceBinding(.x))

                if Set(controls.webSearch?.sources ?? []).isEmpty {
                    Divider()
                    Text("Select at least one source.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .anthropic, .vertexai, .none:
                EmptyView()
            }
        }
    }

    private var mcpToolsEnabledBinding: Binding<Bool> {
        Binding(
            get: { controls.mcpTools?.enabled ?? true },
            set: { enabled in
                if controls.mcpTools == nil {
                    controls.mcpTools = MCPToolsControls(enabled: enabled)
                } else {
                    controls.mcpTools?.enabled = enabled
                }
                persistControlsToConversation()
            }
        )
    }

    @ViewBuilder
    private var mcpToolsMenuContent: some View {
        Toggle("MCP Tools", isOn: mcpToolsEnabledBinding)

        if isMCPToolsEnabled {
            if eligibleMCPServers.isEmpty {
                Divider()
                Text("No MCP servers enabled for automatic tool use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                Text("Servers")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(eligibleMCPServers, id: \.id) { server in
                    Toggle(server.name, isOn: mcpServerSelectionBinding(serverID: server.id))
                }

                if selectedMCPServerIDs.isEmpty {
                    Divider()
                    Text("Select at least one server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if controls.mcpTools?.enabledServerIDs != nil {
                    Divider()
                    Button("Use all servers") {
                        resetMCPServerSelection()
                    }
                }
            }
        }
    }

    private func mcpServerSelectionBinding(serverID: String) -> Binding<Bool> {
        Binding(
            get: {
                selectedMCPServerIDs.contains(serverID)
            },
            set: { isOn in
                if controls.mcpTools == nil {
                    controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
                }

                let eligibleIDs = Set(eligibleMCPServers.map(\.id))
                var selected = Set(controls.mcpTools?.enabledServerIDs ?? Array(eligibleIDs))
                if isOn {
                    selected.insert(serverID)
                } else {
                    selected.remove(serverID)
                }

                let normalized = selected.intersection(eligibleIDs)
                if normalized == eligibleIDs {
                    controls.mcpTools?.enabledServerIDs = nil
                } else {
                    controls.mcpTools?.enabledServerIDs = Array(normalized).sorted()
                }

                persistControlsToConversation()
            }
        )
    }

    private func resetMCPServerSelection() {
        if controls.mcpTools == nil {
            controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
        } else {
            controls.mcpTools?.enabled = true
            controls.mcpTools?.enabledServerIDs = nil
        }
        persistControlsToConversation()
    }

    private func resolvedMCPServerConfigs(for controlsToUse: GenerationControls) -> [MCPServerConfig] {
        guard supportsMCPToolsControl else { return [] }
        guard controlsToUse.mcpTools?.enabled ?? true else { return [] }

        let eligibleServers = mcpServers
            .filter { $0.isEnabled && $0.runToolsAutomatically }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let eligibleIDs = Set(eligibleServers.map(\.id))
        let allowlist = controlsToUse.mcpTools?.enabledServerIDs
        let selectedIDs = allowlist.map(Set.init) ?? eligibleIDs
        let resolvedIDs = selectedIDs.intersection(eligibleIDs)

        return eligibleServers
            .filter { resolvedIDs.contains($0.id) }
            .map { $0.toConfig() }
    }

    private func loadControlsFromConversation() {
        if let decoded = try? JSONDecoder().decode(GenerationControls.self, from: conversationEntity.modelConfigData) {
            controls = decoded
        } else {
            controls = GenerationControls()
        }

        normalizeControlsForCurrentSelection()
    }

    private func persistControlsToConversation() {
        do {
            conversationEntity.modelConfigData = try JSONEncoder().encode(controls)
            conversationEntity.updatedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func setReasoningOff() {
        updateReasoning { reasoning in
            reasoning.enabled = false
        }
        persistControlsToConversation()
    }

    private func setReasoningEffort(_ effort: ReasoningEffort) {
        updateReasoning { reasoning in
            reasoning.enabled = true
            reasoning.effort = effort
            reasoning.budgetTokens = nil
            if providerType == .openai, reasoning.summary == nil {
                reasoning.summary = .auto
            }
        }
        persistControlsToConversation()
    }

    private func setAnthropicThinkingBudget(_ budgetTokens: Int) {
        updateReasoning { reasoning in
            reasoning.enabled = true
            reasoning.effort = nil
            reasoning.budgetTokens = budgetTokens
            reasoning.summary = nil
        }
        persistControlsToConversation()
    }

    private var thinkingBudgetDraftInt: Int? {
        Int(thinkingBudgetDraft.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var maxTokensDraftInt: Int? {
        let trimmed = maxTokensDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    private var thinkingBudgetValidationWarning: String? {
        guard providerType == .anthropic else { return nil }
        guard let budget = thinkingBudgetDraftInt else { return "Enter an integer token budget (e.g., 10000)." }

        if budget <= 0 {
            return "Thinking budget must be a positive integer."
        }

        if let maxTokens = maxTokensDraftInt, maxTokens > 0, budget >= maxTokens {
            return "Note: Anthropic recommends budget_tokens < max_tokens unless using tools + interleaved thinking."
        }

        return "Tip: For Claude 3.7+ / 4.x, max_tokens is a strict limit and includes thinking tokens when enabled."
    }

    private func openThinkingBudgetEditor() {
        let budget = controls.reasoning?.budgetTokens
            ?? selectedReasoningConfig?.defaultBudget
            ?? 2048
        thinkingBudgetDraft = "\(budget)"
        maxTokensDraft = controls.maxTokens.map(String.init) ?? ""
        showingThinkingBudgetSheet = true
    }

    private func applyThinkingBudgetDraft() {
        guard let budgetTokens = thinkingBudgetDraftInt else { return }
        setAnthropicThinkingBudget(budgetTokens)
        controls.maxTokens = maxTokensDraftInt
        persistControlsToConversation()
    }

    private func setReasoningSummary(_ summary: ReasoningSummary) {
        updateReasoning { reasoning in
            reasoning.enabled = true
            reasoning.summary = summary
            if providerType == .openai, (reasoning.effort ?? ReasoningEffort.none) == ReasoningEffort.none {
                reasoning.effort = selectedReasoningConfig?.defaultEffort ?? .medium
            }
        }
        persistControlsToConversation()
    }

    private func updateReasoning(_ mutate: (inout ReasoningControls) -> Void) {
        var reasoning = controls.reasoning ?? ReasoningControls(enabled: false)
        mutate(&reasoning)
        controls.reasoning = reasoning
    }

    private var isOpenAIGPT52SeriesModel: Bool {
        guard providerType == .openai else { return false }
        return conversationEntity.modelID.hasPrefix("gpt-5.2")
    }

    private func defaultWebSearchControls(enabled: Bool) -> WebSearchControls {
        guard enabled else { return WebSearchControls(enabled: false) }

        switch providerType {
        case .openai:
            return WebSearchControls(enabled: true, contextSize: .medium, sources: nil)
        case .xai:
            return WebSearchControls(enabled: true, contextSize: nil, sources: [.web])
        case .anthropic, .vertexai, .none:
            return WebSearchControls(enabled: true, contextSize: nil, sources: nil)
        }
    }

    private func ensureValidWebSearchDefaultsIfEnabled() {
        guard controls.webSearch?.enabled == true else { return }
        switch providerType {
        case .openai:
            controls.webSearch?.sources = nil
            if controls.webSearch?.contextSize == nil {
                controls.webSearch?.contextSize = .medium
            }
        case .xai:
            controls.webSearch?.contextSize = nil
            let sources = controls.webSearch?.sources ?? []
            if sources.isEmpty {
                controls.webSearch?.sources = [.web]
            }
        case .anthropic, .vertexai, .none:
            controls.webSearch?.contextSize = nil
            controls.webSearch?.sources = nil
        }
    }

    private func normalizeControlsForCurrentSelection() {
        // Ensure the stored controls remain valid when switching provider/model.
        let originalData = (try? JSONEncoder().encode(controls)) ?? Data()

        // Reasoning: enforce model's reasoning config expectations.
        if let reasoningConfig = selectedReasoningConfig {
            switch reasoningConfig.type {
            case .effort:
                if controls.reasoning?.enabled == true, controls.reasoning?.effort == nil {
                    updateReasoning { $0.effort = reasoningConfig.defaultEffort ?? .medium }
                }
                controls.reasoning?.budgetTokens = nil
                if providerType == .openai,
                   controls.reasoning?.enabled == true,
                   (controls.reasoning?.effort ?? ReasoningEffort.none) != ReasoningEffort.none,
                   controls.reasoning?.summary == nil {
                    controls.reasoning?.summary = .auto
                }
            case .budget:
                if controls.reasoning?.enabled == true, controls.reasoning?.budgetTokens == nil {
                    updateReasoning { $0.budgetTokens = reasoningConfig.defaultBudget ?? 2048 }
                }
                controls.reasoning?.effort = nil
                controls.reasoning?.summary = nil
            case .none:
                controls.reasoning = nil
            }
        } else {
            // If we don't know, keep user's settings.
        }

        // OpenAI: only GPT-5.2 supports xhigh.
        if providerType == .openai, controls.reasoning?.effort == .xhigh, !isOpenAIGPT52SeriesModel {
            controls.reasoning?.effort = .high
        }

        // Web search defaults & provider-specific fields.
        if controls.webSearch?.enabled == true {
            ensureValidWebSearchDefaultsIfEnabled()
        }

        let newData = (try? JSONEncoder().encode(controls)) ?? Data()
        if newData != originalData {
            persistControlsToConversation()
        }
    }

    private func webSearchSourceBinding(_ source: WebSearchSource) -> Binding<Bool> {
        Binding(
            get: {
                Set(controls.webSearch?.sources ?? []).contains(source)
            },
            set: { isOn in
                var set = Set(controls.webSearch?.sources ?? [])
                if isOn {
                    set.insert(source)
                } else {
                    set.remove(source)
                }
                controls.webSearch?.sources = Array(set).sorted { $0.rawValue < $1.rawValue }
                persistControlsToConversation()
            }
        )
    }
}

// MARK: - Message Row & Content Views

struct MessageRow: View {
    let messageEntity: MessageEntity
    let maxBubbleWidth: CGFloat

    var body: some View {
        let isUser = messageEntity.role == "user"
        let isTool = messageEntity.role == "tool"

        HStack(alignment: .top, spacing: 0) {
            if isUser {
                Spacer()
            }

            ConstrainedWidth(maxBubbleWidth) {
                VStack(alignment: .leading, spacing: 6) {
                    // Header (Sender Name)
                    HStack(spacing: 6) {
                        if !isUser && !isTool {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        }
                        Text(isUser ? "You" : (isTool ? "Tool Output" : "Assistant"))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        if isTool {
                            Image(systemName: "hammer")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                    // Message Content
                    VStack(alignment: .leading, spacing: 8) {
                        if let message = try? messageEntity.toDomain() {
                            ForEach(Array(message.content.enumerated()), id: \.offset) { _, part in
                                ContentPartView(part: part)
                            }

                            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(toolCalls) { call in
                                        ToolCallView(toolCall: call)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(bubbleBackground(isUser: isUser, isTool: isTool))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
            }
            .padding(.horizontal, 16)
            
            if !isUser {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func bubbleBackground(isUser: Bool, isTool: Bool) -> Color {
        if isTool { return Color(nsColor: .controlBackgroundColor).opacity(0.5) }
        if isUser { return Color.accentColor.opacity(0.1) } // Very subtle blue tint
        return Color(nsColor: .controlBackgroundColor) // Standard blocks for assistant
    }
}

struct ContentPartView: View {
    let part: ContentPart

    var body: some View {
        switch part {
        case .text(let text):
            MessageTextView(text: text)

        case .thinking(let thinking):
            ThinkingBlockView(thinking: thinking)

        case .redactedThinking(let redacted):
            RedactedThinkingBlockView(redactedThinking: redacted)

        case .image(let image):
            if let data = image.data, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 500)
                    .cornerRadius(6)
            }

        case .file(let file):
            HStack {
                Image(systemName: "doc")
                Text(file.filename)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)

        case .audio:
            Label("Audio content", systemImage: "waveform")
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
        }
    }
}

struct ToolCallView: View {
    let toolCall: ToolCall
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hammer")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    Text("Tool call")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(toolCall.name)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let argsString = formattedArgumentsJSON {
                        Text(argsString)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.05))
                            )
                    } else {
                        Text("No arguments")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.05))
                            )
                    }

                    if let signature = toolCall.signature, !signature.isEmpty {
                        Text(signature)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedArgumentsJSON: String? {
        let raw = toolCall.arguments.mapValues { $0.value }
        guard JSONSerialization.isValidJSONObject(raw) else { return nil }
        guard let argsJSON = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]),
              let argsString = String(data: argsJSON, encoding: .utf8) else {
            return nil
        }
        return argsString
    }
}

struct StreamingMessageView: View {
    @ObservedObject var state: StreamingMessageState
    let maxBubbleWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ConstrainedWidth(maxBubbleWidth) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        Text("Assistant")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        if !state.thinkingContent.isEmpty {
                            DisclosureGroup(isExpanded: .constant(true)) {
                                Text(state.thinkingContent)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .cornerRadius(6)
                            } label: {
                                HStack {
                                    ProgressView().scaleEffect(0.5)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !state.textContent.isEmpty {
                            MessageTextView(text: state.textContent, mode: .plainText)
                        } else if state.thinkingContent.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.5)
                                Text("Generating...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
            }
            .padding(.horizontal, 16)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

class StreamingMessageState: ObservableObject, Equatable {
    @Published var textContent = ""
    @Published var thinkingContent = ""
    static func == (lhs: StreamingMessageState, rhs: StreamingMessageState) -> Bool {
        lhs.textContent == rhs.textContent && lhs.thinkingContent == rhs.thinkingContent
    }
}
