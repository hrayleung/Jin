import SwiftUI
import SwiftData

struct AssistantInspectorView: View {
    let assistant: AssistantEntity?
    let onRequestDelete: (AssistantEntity) -> Void

    var body: some View {
        Group {
            if let assistant {
                AssistantSettingsEditorView(
                    assistant: assistant,
                    onRequestDelete: onRequestDelete
                )
            } else {
                ContentUnavailableView("Select an Assistant", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 36)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct AssistantSettingsEditorView: View {
    @Bindable var assistant: AssistantEntity

    let onRequestDelete: (AssistantEntity) -> Void

    @State private var customReplyLanguageDraft = ""

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    assistantIcon
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(assistant.displayName)
                            .font(.headline)

                        Text("Defaults used when starting a new chat with this assistant.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }

            Section("Identity") {
                TextField("Name", text: nameBinding)

                HStack(spacing: 10) {
                    TextField("Icon", text: iconBinding, prompt: Text("SF Symbol or emoji"))
                    iconPreview
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.secondary)
                        .help("Preview")
                }

                TextField("Description", text: descriptionBinding, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("Prompt") {
                systemInstructionEditor
            }

            Section("Generation") {
                LabeledContent("Temperature") {
                    HStack(spacing: 10) {
                        Slider(value: temperatureBinding, in: 0...2, step: 0.05)
                            .frame(maxWidth: 220)

                        Text(assistant.temperature, format: .number.precision(.fractionLength(2)))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section {
                DisclosureGroup {
                    LabeledContent("Assistant ID") {
                        Text(assistant.id)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    TextField("Max tokens", text: maxOutputTokensBinding, prompt: Text("Default"))
                        .font(.system(.body, design: .monospaced))

                    Picker("Truncate history", selection: truncateMessagesSettingBinding) {
                        ForEach(TriStateSetting.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Reply language", selection: replyLanguageSelectionBinding) {
                            ForEach(ReplyLanguageOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.menu)

                        if replyLanguageSelectionBinding.wrappedValue == .custom {
                            TextField("Custom language", text: $customReplyLanguageDraft, prompt: Text("e.g. English, 中文, 日本語"))
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: customReplyLanguageDraft) { _, newValue in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    assistant.replyLanguage = trimmed.isEmpty ? nil : trimmed
                                    assistant.updatedAt = Date()
                                }
                        }
                    }
                } label: {
                    Text("Advanced")
                }
            }

            if assistant.id != "default" {
                Section("Danger Zone") {
                    Button(role: .destructive) {
                        onRequestDelete(assistant)
                    } label: {
                        Label("Delete assistant", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            syncCustomReplyLanguageDraft()
        }
        .onChange(of: assistant.replyLanguage) { _, _ in
            syncCustomReplyLanguageDraft()
        }
    }

    private var systemInstructionEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: systemInstructionBinding)
                .font(.body)
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

            if assistant.systemInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Act as …")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 14)
                    .padding(.leading, 14)
                    .allowsHitTesting(false)
            }
        }
    }

    private var iconPreview: some View {
        Group {
            let trimmed = (assistant.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Image(systemName: "person.crop.circle")
            } else if trimmed.count <= 2 {
                Text(trimmed)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: trimmed)
            }
        }
    }

    private var assistantIcon: some View {
        Group {
            let trimmed = (assistant.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            } else if trimmed.count <= 2 {
                Text(trimmed)
                    .font(.system(size: 16))
            } else {
                Image(systemName: trimmed)
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .frame(width: 32, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func syncCustomReplyLanguageDraft() {
        guard replyLanguageSelectionBinding.wrappedValue == .custom else {
            customReplyLanguageDraft = ""
            return
        }
        customReplyLanguageDraft = assistant.replyLanguage ?? ""
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { assistant.name },
            set: { newValue in
                assistant.name = newValue
                assistant.updatedAt = Date()
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
            }
        )
    }

    private var systemInstructionBinding: Binding<String> {
        Binding(
            get: { assistant.systemInstruction },
            set: { newValue in
                assistant.systemInstruction = newValue
                assistant.updatedAt = Date()
            }
        )
    }

    private var temperatureBinding: Binding<Double> {
        Binding(
            get: { assistant.temperature },
            set: { newValue in
                assistant.temperature = newValue
                assistant.updatedAt = Date()
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
                    return
                }

                if let value = Int(trimmed), value > 0 {
                    assistant.maxOutputTokens = value
                    assistant.updatedAt = Date()
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
}

private extension AssistantSettingsEditorView {
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
            case .chineseSimplified: return "中文（简体）"
            case .chineseTraditional: return "中文（繁體）"
            case .japanese: return "日本語"
            case .korean: return "한국어"
            case .custom: return "Custom…"
            }
        }

        var value: String? {
            switch self {
            case .default: return nil
            case .english: return "English"
            case .chineseSimplified: return "中文（简体）"
            case .chineseTraditional: return "中文（繁體）"
            case .japanese: return "日本語"
            case .korean: return "한국어"
            case .custom: return nil
            }
        }
    }

    private var replyLanguageSelectionBinding: Binding<ReplyLanguageOption> {
        Binding(
            get: {
                let trimmed = (assistant.replyLanguage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return .default }

                if let match = ReplyLanguageOption.allCases.first(where: { $0.value == trimmed }) {
                    return match
                }
                return .custom
            },
            set: { newValue in
                switch newValue {
                case .custom:
                    break
                default:
                    assistant.replyLanguage = newValue.value
                    assistant.updatedAt = Date()
                }
                syncCustomReplyLanguageDraft()
            }
        )
    }
}
