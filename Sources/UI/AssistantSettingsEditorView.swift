import SwiftUI
import SwiftData

struct AssistantSettingsEditorView: View {
    @Bindable var assistant: AssistantEntity
    @Environment(\.modelContext) private var modelContext

    @State private var customReplyLanguageDraft = ""
    @State private var replyLanguageSelectionDraft: ReplyLanguageOption = .default
    @State private var isIconPickerPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JinSpacing.large) {
                headerCard

                sectionCard(
                    title: "System Prompt",
                    subtitle: "Base instruction prepended to every request.",
                    systemImage: "text.quote"
                ) {
                    systemInstructionEditor
                }

                sectionCard(
                    title: "Generation Defaults",
                    subtitle: "Model parameter defaults. Can still be overridden per chat.",
                    systemImage: "dial.high"
                ) {
                    VStack(alignment: .leading, spacing: JinSpacing.medium) {
                        VStack(alignment: .leading, spacing: JinSpacing.small) {
                            HStack {
                                Text("Temperature")
                                Spacer()
                                Text(assistant.temperature, format: .number.precision(.fractionLength(2)))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: temperatureBinding, in: 0...2, step: 0.05)
                        }

                        fieldBlock(title: "Max Output Tokens", footer: "Leave empty to follow model default limit.") {
                            HStack(spacing: JinSpacing.small) {
                                TextField("Model default", text: maxOutputTokensBinding)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 160)

                                if assistant.maxOutputTokens != nil {
                                    Button("Clear") {
                                        assistant.maxOutputTokens = nil
                                        assistant.updatedAt = Date()
                                        try? modelContext.save()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                if let tokens = assistant.maxOutputTokens {
                                    Text("\(tokens)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Model default maximum")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }

                sectionCard(
                    title: "Conversation Limits",
                    subtitle: "Keep long chats manageable and context-efficient.",
                    systemImage: "clock.arrow.circlepath"
                ) {
                    VStack(alignment: .leading, spacing: JinSpacing.medium) {
                        VStack(alignment: .leading, spacing: JinSpacing.small) {
                            Text("Truncate History")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Picker("Truncate History", selection: truncateMessagesSettingBinding) {
                                ForEach(TriStateSetting.allCases) { item in
                                    Text(item.label).tag(item)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        if truncateMessagesSettingBinding.wrappedValue == .on {
                            fieldBlock(title: "Keep Last Messages") {
                                HStack(spacing: JinSpacing.small) {
                                    TextField("50", text: maxHistoryMessagesBinding)
                                        .font(.system(.body, design: .monospaced))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 90)
                                    Text("messages")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Text("When enabled, oldest messages are dropped as history grows.")
                            .jinInfoCallout()
                    }
                }

                sectionCard(
                    title: "Response Language",
                    subtitle: "Set a preferred language for assistant replies.",
                    systemImage: "globe"
                ) {
                    VStack(alignment: .leading, spacing: JinSpacing.medium) {
                        HStack {
                            Text("Preset")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $replyLanguageSelectionDraft) {
                                ForEach(ReplyLanguageOption.allCases) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .onChange(of: replyLanguageSelectionDraft) { _, newValue in
                                switch newValue {
                                case .custom:
                                    break
                                default:
                                    assistant.replyLanguage = newValue.value
                                    assistant.updatedAt = Date()
                                    try? modelContext.save()
                                }
                            }
                        }

                        if replyLanguageSelectionDraft == .custom {
                            fieldBlock(title: "Custom Language") {
                                TextField("e.g. English, \u{4E2D}\u{6587}, \u{65E5}\u{672C}\u{8A9E}", text: $customReplyLanguageDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: customReplyLanguageDraft) { _, newValue in
                                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        assistant.replyLanguage = trimmed.isEmpty ? nil : trimmed
                                        assistant.updatedAt = Date()
                                        try? modelContext.save()
                                    }
                            }
                        }
                    }
                }

            }
            .padding(.horizontal, JinSpacing.large)
            .padding(.vertical, JinSpacing.medium)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .background(JinSemanticColor.detailSurface)
        .onAppear {
            syncCustomReplyLanguageDraft()
        }
        .onChange(of: assistant.replyLanguage) { _, _ in
            syncCustomReplyLanguageDraft()
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(alignment: .center, spacing: JinSpacing.medium) {
            Button {
                isIconPickerPresented = true
            } label: {
                assistantIcon
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change icon")
            .help("Change icon")
            .sheet(isPresented: $isIconPickerPresented) {
                AssistantIconPickerSheet(selectedIcon: iconBinding)
            }

            VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                TextField(text: nameBinding, prompt: Text("Assistant name")) { EmptyView() }
                    .font(.title2)
                    .fontWeight(.semibold)
                    .textFieldStyle(.plain)

                TextField(text: descriptionBinding, prompt: Text("Short description\u{2026}")) { EmptyView() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textFieldStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(JinSpacing.medium + 2)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    // MARK: - Reusable Layout

    private func sectionCard<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            HStack(alignment: .top, spacing: JinSpacing.small) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20, height: 20)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(JinSpacing.medium)
        .jinSurface(.raised, cornerRadius: JinRadius.medium)
    }

    private func fieldBlock<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            content()

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - System Instruction

    private var systemInstructionEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: systemInstructionBinding)
                .font(.body)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(JinSpacing.medium)
                .jinSurface(.neutral, cornerRadius: JinRadius.small)

            if assistant.systemInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Act as a helpful assistant. Be concise and clear...")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 18)
                    .padding(.leading, 16)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Icon

    private var assistantIcon: some View {
        Group {
            let trimmed = (assistant.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Image(systemName: "sparkles")
                    .font(.system(size: JinControlMetrics.assistantLargeGlyphSize, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            } else if trimmed.count <= 2 {
                Text(trimmed)
                    .font(.system(size: JinControlMetrics.assistantLargeGlyphSize))
            } else {
                Image(systemName: trimmed)
                    .font(.system(size: JinControlMetrics.assistantLargeGlyphSize, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 56, height: 56)
        .jinSurface(.selected, cornerRadius: JinRadius.large)
    }

    // MARK: - Reply Language

    private func syncCustomReplyLanguageDraft() {
        let resolved = resolvedReplyLanguageOption(from: assistant.replyLanguage)
        replyLanguageSelectionDraft = resolved

        guard resolved == .custom else {
            customReplyLanguageDraft = ""
            return
        }
        customReplyLanguageDraft = assistant.replyLanguage ?? ""
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { assistant.name },
            set: { newValue in
                assistant.name = newValue
                assistant.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { assistant.assistantDescription ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                assistant.assistantDescription = trimmed.isEmpty ? nil : trimmed
                assistant.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var iconBinding: Binding<String> {
        Binding(
            get: { assistant.icon ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                assistant.icon = trimmed.isEmpty ? nil : trimmed
                assistant.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var systemInstructionBinding: Binding<String> {
        Binding(
            get: { assistant.systemInstruction },
            set: { newValue in
                assistant.systemInstruction = newValue
                assistant.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var temperatureBinding: Binding<Double> {
        Binding(
            get: { assistant.temperature },
            set: { newValue in
                assistant.temperature = newValue
                assistant.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var maxOutputTokensBinding: Binding<String> {
        Binding(
            get: { assistant.maxOutputTokens.map(String.init) ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    assistant.maxOutputTokens = nil
                    assistant.updatedAt = Date()
                    try? modelContext.save()
                    return
                }

                if let value = Int(trimmed), value > 0 {
                    assistant.maxOutputTokens = value
                    assistant.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        )
    }

    private var maxHistoryMessagesBinding: Binding<String> {
        Binding(
            get: { assistant.maxHistoryMessages.map(String.init) ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    assistant.maxHistoryMessages = nil
                    assistant.updatedAt = Date()
                    try? modelContext.save()
                    return
                }

                if let value = Int(trimmed), value > 0 {
                    assistant.maxHistoryMessages = value
                    assistant.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        )
    }

    private enum TriStateSetting: String, CaseIterable, Identifiable {
        case `default`
        case on
        case off

        var id: String { rawValue }

        var label: String {
            switch self {
            case .default: return "Default"
            case .on: return "On"
            case .off: return "Off"
            }
        }
    }

    private var truncateMessagesSettingBinding: Binding<TriStateSetting> {
        Binding(
            get: {
                switch assistant.truncateMessages {
                case true: return .on
                case false: return .off
                case nil: return .default
                }
            },
            set: { newValue in
                switch newValue {
                case .default:
                    assistant.truncateMessages = nil
                case .on:
                    assistant.truncateMessages = true
                case .off:
                    assistant.truncateMessages = false
                }
                assistant.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private enum ReplyLanguageOption: String, CaseIterable, Identifiable {
        case `default`
        case english
        case chineseSimplified
        case chineseTraditional
        case japanese
        case korean
        case custom

        var id: String { rawValue }

        var label: String {
            switch self {
            case .default: return "Default"
            case .english: return "English"
            case .chineseSimplified: return "\u{4E2D}\u{6587}\u{FF08}\u{7B80}\u{4F53}\u{FF09}"
            case .chineseTraditional: return "\u{4E2D}\u{6587}\u{FF08}\u{7E41}\u{9AD4}\u{FF09}"
            case .japanese: return "\u{65E5}\u{672C}\u{8A9E}"
            case .korean: return "\u{D55C}\u{AD6D}\u{C5B4}"
            case .custom: return "Custom\u{2026}"
            }
        }

        var value: String? {
            switch self {
            case .default: return nil
            case .english: return "English"
            case .chineseSimplified: return "\u{4E2D}\u{6587}\u{FF08}\u{7B80}\u{4F53}\u{FF09}"
            case .chineseTraditional: return "\u{4E2D}\u{6587}\u{FF08}\u{7E41}\u{9AD4}\u{FF09}"
            case .japanese: return "\u{65E5}\u{672C}\u{8A9E}"
            case .korean: return "\u{D55C}\u{AD6D}\u{C5B4}"
            case .custom: return nil
            }
        }
    }

    private func resolvedReplyLanguageOption(from language: String?) -> ReplyLanguageOption {
        let trimmed = (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .default }

        if let match = ReplyLanguageOption.allCases.first(where: { $0.value == trimmed }) {
            return match
        }
        return .custom
    }
}
