import SwiftData
import SwiftUI

struct AssistantSettingsEditorView: View {
    @Bindable var assistant: AssistantEntity
    @Environment(\.modelContext) private var modelContext

    @State private var customReplyLanguageDraft = ""
    @State private var replyLanguageSelectionDraft: AssistantReplyLanguageOption = .default
    @State private var isIconPickerPresented = false

    var body: some View {
        JinSettingsPage {
            AssistantSettingsIdentityHeader(
                name: nameBinding,
                assistantDescription: descriptionBinding,
                icon: iconBinding,
                isIconPickerPresented: $isIconPickerPresented
            )

            AssistantSystemPromptSection(systemInstruction: systemInstructionBinding)

            AssistantGenerationDefaultsSection(
                temperature: temperatureBinding,
                maxOutputTokens: assistant.maxOutputTokens,
                maxOutputTokensDraft: maxOutputTokensBinding,
                clearMaxOutputTokens: clearMaxOutputTokens
            )

            AssistantConversationLimitsSection(
                truncateMessagesSetting: truncateMessagesSettingBinding,
                maxHistoryMessages: maxHistoryMessagesBinding
            )

            AssistantReplyLanguageSection(
                selection: $replyLanguageSelectionDraft,
                customLanguage: $customReplyLanguageDraft,
                didSelectPreset: applyReplyLanguageSelection,
                didChangeCustomLanguage: applyCustomReplyLanguage
            )
        }
        .onAppear {
            syncCustomReplyLanguageDraft()
        }
        .onChange(of: assistant.replyLanguage) { _, _ in
            syncCustomReplyLanguageDraft()
        }
    }

    // MARK: - Reply Language

    private func syncCustomReplyLanguageDraft() {
        let resolved = AssistantReplyLanguageOption.resolved(from: assistant.replyLanguage)
        replyLanguageSelectionDraft = resolved

        guard resolved == .custom else {
            customReplyLanguageDraft = ""
            return
        }
        customReplyLanguageDraft = assistant.replyLanguage ?? ""
    }

    private func applyReplyLanguageSelection(_ selection: AssistantReplyLanguageOption) {
        guard selection != .custom else { return }
        persistAssistantChange {
            assistant.replyLanguage = selection.value
        }
    }

    private func applyCustomReplyLanguage(_ language: String) {
        persistAssistantChange {
            assistant.replyLanguage = AssistantSettingsEditorSupport.normalizedCustomReplyLanguage(language)
        }
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { assistant.name },
            set: { newValue in
                persistAssistantChange {
                    assistant.name = newValue
                }
            }
        )
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { assistant.assistantDescription ?? "" },
            set: { newValue in
                persistAssistantChange {
                    assistant.assistantDescription = AssistantSettingsEditorSupport.normalizedAssistantDescription(newValue)
                }
            }
        )
    }

    private var iconBinding: Binding<String> {
        Binding(
            get: { assistant.icon ?? "" },
            set: { newValue in
                persistAssistantChange {
                    assistant.icon = AssistantSettingsEditorSupport.normalizedIcon(newValue)
                }
            }
        )
    }

    private var systemInstructionBinding: Binding<String> {
        Binding(
            get: { assistant.systemInstruction },
            set: { newValue in
                persistAssistantChange {
                    assistant.systemInstruction = newValue
                }
            }
        )
    }

    /// Quantized to `temperatureStep` in the setter rather than via `Slider(step:)`,
    /// which would make AppKit draw a tick mark for each of the 40 steps. The knob
    /// still snaps because `get` returns the quantized value, and a drag persists at
    /// most once per step instead of once per pixel.
    private var temperatureBinding: Binding<Double> {
        Binding(
            get: { assistant.temperature },
            set: { newValue in
                let quantized = (newValue / Self.temperatureStep).rounded() * Self.temperatureStep
                guard abs(quantized - assistant.temperature) > Self.temperatureStep / 10 else { return }
                persistAssistantChange {
                    assistant.temperature = quantized
                }
            }
        )
    }

    private static let temperatureStep = 0.05

    private var maxOutputTokensBinding: Binding<String> {
        Binding(
            get: { assistant.maxOutputTokens.map(String.init) ?? "" },
            set: { newValue in
                applyOptionalPositiveIntegerDraft(newValue) { value in
                    assistant.maxOutputTokens = value
                }
            }
        )
    }

    private var maxHistoryMessagesBinding: Binding<String> {
        Binding(
            get: { assistant.maxHistoryMessages.map(String.init) ?? "" },
            set: { newValue in
                applyOptionalPositiveIntegerDraft(newValue) { value in
                    assistant.maxHistoryMessages = value
                }
            }
        )
    }

    private func clearMaxOutputTokens() {
        persistAssistantChange {
            assistant.maxOutputTokens = nil
        }
    }

    private var truncateMessagesSettingBinding: Binding<AssistantTruncateHistorySetting> {
        Binding(
            get: {
                switch assistant.truncateMessages {
                case true: return .on
                case false: return .off
                case nil: return .default
                }
            },
            set: { newValue in
                persistAssistantChange {
                    switch newValue {
                    case .default:
                        assistant.truncateMessages = nil
                    case .on:
                        assistant.truncateMessages = true
                    case .off:
                        assistant.truncateMessages = false
                    }
                }
            }
        )
    }

    private func applyOptionalPositiveIntegerDraft(
        _ draft: String,
        assign: (Int?) -> Void
    ) {
        switch AssistantSettingsEditorSupport.optionalPositiveIntegerDraft(from: draft) {
        case .clear:
            persistAssistantChange {
                assign(nil)
            }
        case .value(let value):
            persistAssistantChange {
                assign(value)
            }
        case .invalid:
            return
        }
    }

    private func persistAssistantChange(_ apply: () -> Void) {
        apply()
        assistant.updatedAt = Date()
        try? modelContext.save()
    }
}
