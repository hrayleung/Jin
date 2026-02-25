import SwiftUI
import SwiftData

struct AssistantInspectorView: View {
    let assistant: AssistantEntity

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AssistantSettingsEditorView(
                assistant: assistant
            )
            .navigationTitle("Assistant Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 700, idealHeight: 800)
    }
}

// Icon Picker Component
private struct IconPickerButton: View {
    @Binding var selectedIcon: String
    @State private var isPickerPresented = false

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: JinSpacing.small) {
                iconPreview
                    .frame(width: JinControlMetrics.iconButtonHitSize, height: JinControlMetrics.iconButtonHitSize)
                    .jinSurface(.selected, cornerRadius: JinRadius.small)

                Text(selectedIcon.isEmpty ? "Choose…" : selectedIcon)
                    .font(.body)
                    .foregroundStyle(selectedIcon.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, JinSpacing.medium - 2)
            .padding(.vertical, JinSpacing.xSmall + 2)
            .jinSurface(.neutral, cornerRadius: JinRadius.small)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPickerPresented) {
            IconPickerSheet(selectedIcon: $selectedIcon)
        }
    }

    private var iconPreview: some View {
        Group {
            let trimmed = selectedIcon.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: JinControlMetrics.assistantGlyphSize, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else if trimmed.count <= 2 {
                Text(trimmed)
                    .font(.system(size: JinControlMetrics.assistantGlyphSize))
            } else {
                Image(systemName: trimmed)
                    .font(.system(size: JinControlMetrics.assistantGlyphSize, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

private struct IconCategory: Identifiable {
    let id = UUID()
    let name: String
    let icons: [String]
}

private struct IconPickerSheet: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var draftIcon = ""

    let iconOptions: [IconCategory] = [
        IconCategory(
            name: "Characters",
            icons: ["person.crop.circle", "person.fill", "person.2.fill", "figure.wave", "sparkles", "star.fill", "heart.fill", "face.smiling", "crown.fill", "moon.stars.fill"]
        ),
        IconCategory(
            name: "Technology",
            icons: ["laptopcomputer", "desktopcomputer", "iphone", "applewatch", "brain", "cpu", "antenna.radiowaves.left.and.right", "waveform", "bolt.fill", "lightbulb.fill"]
        ),
        IconCategory(
            name: "Communication",
            icons: ["bubble.left.and.bubble.right", "message.fill", "envelope.fill", "phone.fill", "video.fill", "mic.fill", "speaker.wave.3.fill", "quote.bubble", "megaphone.fill", "bell.fill"]
        ),
        IconCategory(
            name: "Creative",
            icons: ["paintbrush.fill", "pencil", "pencil.and.outline", "book.fill", "doc.text.fill", "photo.fill", "music.note", "film", "camera.fill", "theatermasks.fill"]
        ),
        IconCategory(
            name: "Business",
            icons: ["briefcase.fill", "chart.line.uptrend.xyaxis", "dollarsign.circle.fill", "building.2.fill", "cart.fill", "creditcard.fill", "paperplane.fill", "folder.fill", "calendar", "clock.fill"]
        ),
        IconCategory(
            name: "Science",
            icons: ["graduationcap.fill", "atom", "flask.fill", "testtube.2", "leaf.fill", "globe", "pawprint.fill", "dna", "fossil.shell.fill", "mountain.2.fill"]
        ),
        IconCategory(
            name: "Emoji & Custom",
            icons: ["🤖", "🎨", "💡", "🚀", "⚡️", "🎯", "🔥", "✨", "🌟", "💫"]
        )
    ]

    var filteredCategories: [IconCategory] {
        if searchText.isEmpty {
            return iconOptions
        }

        return iconOptions.compactMap { category in
            let filtered = category.icons.filter { icon in
                icon.localizedCaseInsensitiveContains(searchText)
            }
            return filtered.isEmpty ? nil : IconCategory(name: category.name, icons: filtered)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if searchText.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("None")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            Button {
                                draftIcon = ""
                            } label: {
                                HStack(spacing: JinSpacing.small) {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, height: 44)
                                        .jinSurface(draftIcon.isEmpty ? .selected : .neutral, cornerRadius: JinRadius.medium)

                                    Text("No Icon")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .jinSurface(.raised, cornerRadius: JinRadius.medium)
                    }

                    ForEach(filteredCategories) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.name)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                                ForEach(category.icons, id: \.self) { icon in
                                    IconButton(
                                        icon: icon,
                                        isSelected: draftIcon == icon
                                    ) {
                                        draftIcon = icon
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .jinSurface(.raised, cornerRadius: JinRadius.medium)
                    }
                }
                .padding(20)
            }
            .background(JinSemanticColor.detailSurface)
            .navigationTitle("Choose Icon")
            .searchable(text: $searchText, prompt: "Search icons...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selectedIcon = draftIcon
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .onAppear {
            draftIcon = selectedIcon
        }
    }
}

private struct IconButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            iconView
                .frame(width: 44, height: 44)
                .jinSurface(isSelected ? .selected : .neutral, cornerRadius: JinRadius.medium)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconView: some View {
        if icon.count <= 2 {
            Text(icon)
                .font(.system(size: 24))
        } else {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
    }
}

private struct AssistantSettingsEditorView: View {
    @Bindable var assistant: AssistantEntity
    @Environment(\.modelContext) private var modelContext

    @State private var customReplyLanguageDraft = ""
    @State private var replyLanguageSelectionDraft: ReplyLanguageOption = .default

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JinSpacing.large) {
                VStack(alignment: .leading, spacing: JinSpacing.medium) {
                    HStack(alignment: .center, spacing: JinSpacing.medium) {
                        assistantIcon
                            .frame(width: 56, height: 56)

                        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                            Text(assistant.displayName)
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("Tune this assistant’s behavior defaults for every new chat.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: JinSpacing.small)],
                        alignment: .leading,
                        spacing: JinSpacing.small
                    ) {
                        overviewPill(title: "Temperature", value: temperatureSummaryText)
                        overviewPill(title: "Max Tokens", value: maxTokensSummaryText)
                        overviewPill(title: "History", value: historySummaryText)
                        overviewPill(title: "Reply Language", value: replyLanguageSummaryText)
                    }
                }
                .padding(JinSpacing.medium + 2)
                .jinSurface(.raised, cornerRadius: JinRadius.large)

                sectionCard(
                    title: "Identity",
                    subtitle: "How this assistant appears in your workspace.",
                    systemImage: "person.crop.circle"
                ) {
                    VStack(alignment: .leading, spacing: JinSpacing.medium) {
                        fieldBlock(title: "Name") {
                            TextField("e.g., Code Assistant", text: nameBinding)
                                .textFieldStyle(.roundedBorder)
                        }

                        fieldBlock(title: "Icon") {
                            IconPickerButton(selectedIcon: iconBinding)
                        }

                        fieldBlock(title: "Description", footer: "Shown in assistant picker and sidebar hints.") {
                            TextField("e.g., Helps with coding", text: descriptionBinding, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

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
                                TextField("e.g., 4096", text: maxOutputTokensBinding)
                                    .font(.system(.body, design: .monospaced))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)

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
                                    Text("No limit")
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
                                TextField("e.g. English, 中文, 日本語", text: $customReplyLanguageDraft)
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

    private func overviewPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, JinSpacing.small + 2)
        .padding(.vertical, JinSpacing.small)
        .jinSurface(.neutral, cornerRadius: JinRadius.small)
    }

    private var temperatureSummaryText: String {
        assistant.temperature.formatted(.number.precision(.fractionLength(2)))
    }

    private var maxTokensSummaryText: String {
        assistant.maxOutputTokens.map(String.init) ?? "No limit"
    }

    private var historySummaryText: String {
        switch assistant.truncateMessages {
        case nil:
            return "Default"
        case false:
            return "Unlimited"
        case true:
            if let value = assistant.maxHistoryMessages, value > 0 {
                return "Keep \(value)"
            }
            return "On"
        }
    }

    private var replyLanguageSummaryText: String {
        let trimmed = (assistant.replyLanguage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Default" : trimmed
    }

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

    private func syncCustomReplyLanguageDraft() {
        let resolved = resolvedReplyLanguageOption(from: assistant.replyLanguage)
        replyLanguageSelectionDraft = resolved

        guard resolved == .custom else {
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

    private func resolvedReplyLanguageOption(from language: String?) -> ReplyLanguageOption {
        let trimmed = (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .default }

        if let match = ReplyLanguageOption.allCases.first(where: { $0.value == trimmed }) {
            return match
        }
        return .custom
    }
}
