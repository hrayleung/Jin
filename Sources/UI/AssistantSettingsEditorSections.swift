import SwiftUI

struct AssistantSettingsIdentityHeader: View {
    @Binding var name: String
    @Binding var assistantDescription: String
    @Binding var icon: String
    @Binding var isIconPickerPresented: Bool

    var body: some View {
        HStack(alignment: .center, spacing: JinSpacing.large) {
            Button {
                isIconPickerPresented = true
            } label: {
                AssistantSettingsIconPreview(icon: icon)
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

struct AssistantSystemPromptSection: View {
    @Binding var systemInstruction: String

    var body: some View {
        JinSettingsSection(
            "System Prompt",
            detail: "Sent at the start of every conversation with this assistant."
        ) {
            JinSettingsTextEditor(
                text: $systemInstruction,
                placeholder: "Base system prompt",
                minHeight: 120,
                usesMonospacedFont: false,
                placeholderLeadingPadding: 4
            )
        }
    }
}

struct AssistantGenerationDefaultsSection: View {
    @Binding var temperature: Double
    let maxOutputTokens: Int?
    @Binding var maxOutputTokensDraft: String
    let clearMaxOutputTokens: () -> Void

    var body: some View {
        JinSettingsSection(
            "Generation Defaults",
            detail: "Applied to every new conversation."
        ) {
            JinSettingsSliderValueRow(
                title: "Temperature",
                value: $temperature,
                range: 0...2
            )

            JinSettingsControlRow(
                "Max Output Tokens",
                supportingText: "Leave empty to follow the model\u{2019}s own limit."
            ) {
                HStack(spacing: JinSpacing.small) {
                    JinSettingsTextField(
                        "Model default",
                        text: $maxOutputTokensDraft,
                        usesMonospacedFont: true
                    )
                    .frame(maxWidth: 160)

                    Button("Clear", action: clearMaxOutputTokens)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(maxOutputTokens == nil)

                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct AssistantConversationLimitsSection: View {
    @Binding var truncateMessagesSetting: AssistantTruncateHistorySetting
    @Binding var maxHistoryMessages: String

    var body: some View {
        JinSettingsSection(
            "Conversation Limits",
            detail: "Oldest messages are dropped as the conversation grows."
        ) {
            JinSettingsControlRow("Truncate History") {
                JinSettingsSegmentedPicker(
                    "Truncate History",
                    selection: $truncateMessagesSetting
                ) {
                    ForEach(AssistantTruncateHistorySetting.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
            }

            if truncateMessagesSetting == .on {
                JinSettingsControlRow("Keep Last Messages") {
                    HStack(spacing: JinSpacing.small) {
                        JinSettingsTextField("50", text: $maxHistoryMessages, usesMonospacedFont: true)
                            .frame(width: 90)

                        Text("messages")
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: truncateMessagesSetting)
    }
}

struct AssistantReplyLanguageSection: View {
    @Binding var selection: AssistantReplyLanguageOption
    @Binding var customLanguage: String
    let didSelectPreset: (AssistantReplyLanguageOption) -> Void
    let didChangeCustomLanguage: (String) -> Void

    var body: some View {
        JinSettingsSection("Response Language") {
            JinSettingsPickerRow("Preset", selection: $selection) {
                ForEach(AssistantReplyLanguageOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .onChange(of: selection) { _, newValue in
                didSelectPreset(newValue)
            }

            if selection == .custom {
                JinSettingsTextFieldRow(
                    "Custom Language",
                    fieldTitle: "e.g. English, \u{4E2D}\u{6587}, \u{65E5}\u{672C}\u{8A9E}",
                    text: $customLanguage
                )
                .onChange(of: customLanguage) { _, newValue in
                    didChangeCustomLanguage(newValue)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selection)
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
