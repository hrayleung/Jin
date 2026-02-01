import SwiftUI
import SwiftData

struct AssistantInspectorView: View {
    let assistant: AssistantEntity?
    let onRequestDelete: (AssistantEntity) -> Void

    var body: some View {
        if let assistant {
            AssistantSettingsFormView(
                assistant: assistant,
                onRequestDelete: onRequestDelete
            )
        } else {
            ContentUnavailableView("Select an Assistant", systemImage: "person.crop.circle")
                .padding()
        }
    }
}

private struct AssistantSettingsFormView: View {
    private enum FocusField: Hashable {
        case id
    }

    @Query(sort: \AssistantEntity.sortOrder, order: .forward) private var assistants: [AssistantEntity]
    @Bindable var assistant: AssistantEntity

    let onRequestDelete: (AssistantEntity) -> Void

    @State private var idDraft = ""
    @State private var customReplyLanguageDraft = ""
    @State private var idValidationMessage: String?
    @FocusState private var focusedField: FocusField?

    var body: some View {
        Form {
            Section {
                Text("Assistant settings are used as default settings for every chat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Identity") {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    TextField("ID", text: $idDraft)
                        .focused($focusedField, equals: .id)
                        .textFieldStyle(.roundedBorder)
                        .disabled(assistant.id == "default")
                        .onSubmit {
                            commitAssistantIDIfValid()
                        }
                        .onChange(of: focusedField) { oldValue, newValue in
                            guard oldValue == .id, newValue != .id else { return }
                            commitAssistantIDIfValid()
                        }

                    if let message = idValidationMessage, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    TextField("Icon (SF Symbol)", text: iconBinding)
                        .textFieldStyle(.roundedBorder)

                    iconPreview
                        .frame(width: 22, height: 22)
                        .foregroundStyle(.secondary)
                        .help("Preview")
                }

                TextField("Name", text: nameBinding)
                    .textFieldStyle(.roundedBorder)

                TextField("Description", text: descriptionBinding, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...8)
            }

            Section("Behavior") {
                systemInstructionEditor

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(assistant.temperature, format: .number.precision(.fractionLength(2)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: temperatureBinding, in: 0...2, step: 0.05)
                    HStack {
                        Text("Precise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Creative")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                TextField("Max output tokens", text: maxOutputTokensBinding, prompt: Text("Default"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Picker("Truncate messages", selection: truncateMessagesSettingBinding) {
                    ForEach(TriStateSetting.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.menu)

                Picker("Reply language", selection: replyLanguageSelectionBinding) {
                    ForEach(ReplyLanguageOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)

                if replyLanguageSelectionBinding.wrappedValue == .custom {
                    TextField("Custom reply language", text: $customReplyLanguageDraft, prompt: Text("e.g. English, 中文, 日本語"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customReplyLanguageDraft) { _, newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            assistant.replyLanguage = trimmed.isEmpty ? nil : trimmed
                            assistant.updatedAt = Date()
                        }
                }
            }

            Section {
                Button(role: .destructive) {
                    onRequestDelete(assistant)
                } label: {
                    Label("Delete assistant", systemImage: "trash")
                }
                .disabled(assistant.id == "default")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            idDraft = assistant.id
            syncCustomReplyLanguageDraft()
        }
        .onChange(of: assistant.id) { _, newValue in
            if idDraft != newValue {
                idDraft = newValue
            }
        }
        .onChange(of: assistant.replyLanguage) { _, _ in
            syncCustomReplyLanguageDraft()
        }
    }

    private var systemInstructionEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("System instruction")
                .font(.subheadline)
            ZStack(alignment: .topLeading) {
                TextEditor(text: systemInstructionBinding)
                    .frame(minHeight: 120)

                if assistant.systemInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Act as …")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 6)
                }
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
                    .font(.system(size: 18))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: trimmed)
            }
        }
    }

    private func syncCustomReplyLanguageDraft() {
        guard replyLanguageSelectionBinding.wrappedValue == .custom else {
            customReplyLanguageDraft = ""
            return
        }
        customReplyLanguageDraft = assistant.replyLanguage ?? ""
    }

    private func commitAssistantIDIfValid() {
        guard assistant.id != "default" else {
            idDraft = assistant.id
            idValidationMessage = nil
            return
        }

        let trimmed = idDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            idValidationMessage = "ID can’t be empty."
            return
        }

        guard trimmed.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            idValidationMessage = "Use letters, numbers, '-' or '_'."
            return
        }

        let conflict = assistants.contains(where: { $0.id == trimmed && $0 !== assistant })
        guard !conflict else {
            idValidationMessage = "ID already exists."
            return
        }

        if assistant.id != trimmed {
            assistant.id = trimmed
            assistant.updatedAt = Date()
        }

        idDraft = trimmed
        idValidationMessage = nil
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

