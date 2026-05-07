import SwiftUI

struct AssistantSettingsHeaderCard: View {
    @Binding var name: String
    @Binding var assistantDescription: String
    @Binding var icon: String
    @Binding var isIconPickerPresented: Bool

    var body: some View {
        JinSettingsCard(spacing: JinSpacing.medium, padding: JinSpacing.medium + 2) {
            HStack(alignment: .center, spacing: JinSpacing.medium) {
                Button {
                    isIconPickerPresented = true
                } label: {
                    AssistantSettingsIconPreview(icon: icon)
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change icon")
                .help("Change icon")
                .sheet(isPresented: $isIconPickerPresented) {
                    AssistantIconPickerSheet(selectedIcon: $icon)
                }

                VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                    TextField(text: $name, prompt: Text("Assistant name")) { EmptyView() }
                        .font(.title2)
                        .fontWeight(.semibold)
                        .textFieldStyle(.plain)

                    TextField(text: $assistantDescription, prompt: Text("Short description\u{2026}")) { EmptyView() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textFieldStyle(.plain)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

struct AssistantSettingsSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    private let content: () -> Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        JinSettingsCard(spacing: JinSpacing.medium, padding: JinSpacing.medium, cornerRadius: JinRadius.medium) {
            HStack(alignment: .top, spacing: JinSpacing.small) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20, height: 20)
                    .padding(.top, 1)

                Text(title)
                    .font(.headline)
            }

            content()
        }
    }
}

struct AssistantSettingsFieldBlock<Content: View>: View {
    let title: String
    let footer: String?
    private let content: () -> Content

    init(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
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
}

struct AssistantSystemInstructionEditor: View {
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(JinSpacing.medium)
                .jinSurface(.neutral, cornerRadius: JinRadius.small)

            if text.trimmedNonEmpty == nil {
                Text("Base system prompt")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 18)
                    .padding(.leading, 16)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct AssistantSettingsIconPreview: View {
    let icon: String

    var body: some View {
        let trimmed = AssistantGlyphRendering.normalizedGlyph(icon)
        let isSymbol = AssistantGlyphRendering.isSFSymbolName(trimmed)

        Group {
            if trimmed.isEmpty {
                Image(systemName: "sparkles")
                    .font(.system(size: JinControlMetrics.assistantLargeGlyphSize, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            } else if isSymbol {
                Image(systemName: trimmed)
                    .font(.system(size: JinControlMetrics.assistantLargeGlyphSize, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Text(trimmed)
                    .font(.system(size: JinControlMetrics.assistantLargeGlyphSize))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 56, height: 56)
        .jinSurface(.selected, cornerRadius: JinRadius.large)
    }
}

struct AssistantGenerationDefaultsSection: View {
    let temperature: Double
    @Binding var temperatureBinding: Double
    let maxOutputTokens: Int?
    @Binding var maxOutputTokensBinding: String
    let clearMaxOutputTokens: () -> Void

    var body: some View {
        AssistantSettingsSectionCard(
            title: "Generation Defaults",
            systemImage: "dial.high"
        ) {
            VStack(alignment: .leading, spacing: JinSpacing.medium) {
                temperatureControl
                maxOutputTokensControl
            }
        }
    }

    private var temperatureControl: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            HStack {
                Text("Temperature")
                Spacer()
                Text(temperature, format: .number.precision(.fractionLength(2)))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: $temperatureBinding, in: 0...2, step: 0.05)
        }
    }

    private var maxOutputTokensControl: some View {
        AssistantSettingsFieldBlock(
            title: "Max Output Tokens",
            footer: "Leave empty to follow model default limit."
        ) {
            HStack(spacing: JinSpacing.small) {
                TextField("Model default", text: $maxOutputTokensBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)

                if maxOutputTokens != nil {
                    Button("Clear", action: clearMaxOutputTokens)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                maxOutputTokensValueText
            }
        }
    }

    @ViewBuilder
    private var maxOutputTokensValueText: some View {
        if let maxOutputTokens {
            Text("\(maxOutputTokens)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        } else {
            Text("Model default maximum")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

struct AssistantConversationLimitsSection: View {
    @Binding var truncateMessagesSetting: AssistantTruncateHistorySetting
    @Binding var maxHistoryMessages: String

    var body: some View {
        AssistantSettingsSectionCard(
            title: "Conversation Limits",
            systemImage: "clock.arrow.circlepath"
        ) {
            VStack(alignment: .leading, spacing: JinSpacing.medium) {
                truncateHistoryControl

                keepLastMessagesControl

                historyFooterText
            }
        }
    }

    private var truncateHistoryControl: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text("Truncate History")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Truncate History", selection: $truncateMessagesSetting) {
                ForEach(AssistantTruncateHistorySetting.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var keepLastMessagesControl: some View {
        if truncateMessagesSetting == .on {
            AssistantSettingsFieldBlock(title: "Keep Last Messages") {
                HStack(spacing: JinSpacing.small) {
                    JinSettingsTextField("50", text: $maxHistoryMessages, usesMonospacedFont: true)
                        .frame(width: 90)

                    Text("messages")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var historyFooterText: some View {
        Text("Oldest messages are dropped as history grows.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct AssistantReplyLanguageSection: View {
    @Binding var selection: AssistantReplyLanguageOption
    @Binding var customLanguage: String
    let didSelectPreset: (AssistantReplyLanguageOption) -> Void
    let didChangeCustomLanguage: (String) -> Void

    var body: some View {
        AssistantSettingsSectionCard(
            title: "Response Language",
            systemImage: "globe"
        ) {
            VStack(alignment: .leading, spacing: JinSpacing.medium) {
                presetPickerRow

                customLanguageField
            }
        }
    }

    private var presetPickerRow: some View {
        HStack {
            Text("Preset")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Picker("", selection: $selection) {
                ForEach(AssistantReplyLanguageOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .onChange(of: selection) { _, newValue in
                didSelectPreset(newValue)
            }
        }
    }

    @ViewBuilder
    private var customLanguageField: some View {
        if selection == .custom {
            AssistantSettingsFieldBlock(title: "Custom Language") {
                TextField("e.g. English, \u{4E2D}\u{6587}, \u{65E5}\u{672C}\u{8A9E}", text: $customLanguage)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: customLanguage) { _, newValue in
                        didChangeCustomLanguage(newValue)
                    }
            }
        }
    }
}

enum AssistantTruncateHistorySetting: String, CaseIterable, Identifiable {
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

enum AssistantReplyLanguageOption: String, CaseIterable, Identifiable {
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

    static func resolved(from language: String?) -> AssistantReplyLanguageOption {
        guard let trimmed = language?.trimmedNonEmpty else { return .default }

        if let match = allCases.first(where: { $0.value == trimmed }) {
            return match
        }
        return .custom
    }
}
