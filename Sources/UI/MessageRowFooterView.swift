import SwiftUI

struct MessageRowFooterView: View {
    let itemID: UUID
    let timestamp: Date
    let isUser: Bool
    let isAssistant: Bool
    let isEditingUserMessage: Bool
    let showsCopyButton: Bool
    let copyText: String
    let canEditUserMessage: Bool
    let canDeleteResponse: Bool
    let responseMetrics: ResponseMetrics?
    let textToSpeechEnabled: Bool
    let textToSpeechConfigured: Bool
    let textToSpeechIsGenerating: Bool
    let textToSpeechIsPlaying: Bool
    let textToSpeechIsPaused: Bool
    let onToggleSpeakAssistantMessage: (UUID, String) -> Void
    let onStopSpeakAssistantMessage: (UUID) -> Void
    let onRegenerate: (UUID) -> Void
    let onEditUserMessage: (UUID) -> Void
    let onDeleteMessage: (UUID) -> Void
    let onDeleteResponse: (UUID) -> Void
    let onSubmitUserEdit: (UUID) -> Void
    let onCancelUserEdit: () -> Void

    @State private var isResponseMetricsPopoverPresented = false
    @State private var showingDeleteConfirmation = false
    @State private var pendingDeleteAction: DeleteAction?

    private enum DeleteAction {
        case message
        case response
    }

    var body: some View {
        Group {
            if isAssistant {
                assistantFooter
            } else if isUser {
                userFooter
            }
        }
        .alert(
            pendingDeleteAction == .response ? "Delete response?" : "Delete message?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                performPendingDelete()
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteAction = nil
            }
        }
    }

    private var assistantFooter: some View {
        HStack(spacing: JinSpacing.small) {
            if showsCopyButton {
                CopyToPasteboardButton(text: copyText, helpText: "Copy message", useProminentStyle: false)
                    .accessibilityLabel("Copy message")
            }

            if let responseMetrics {
                actionIconButton(systemName: "gauge", helpText: "Response metrics") {
                    isResponseMetricsPopoverPresented.toggle()
                }
                .popover(isPresented: $isResponseMetricsPopoverPresented, arrowEdge: .top) {
                    ResponseMetricsPopover(metrics: responseMetrics)
                }
            }

            if textToSpeechEnabled {
                speechControls
            }

            actionIconButton(systemName: "arrow.clockwise", helpText: "Regenerate") {
                onRegenerate(itemID)
            }

            Menu {
                Button(role: .destructive) {
                    requestDelete(.message)
                } label: {
                    deleteActionMenuLabel("Delete message", systemImage: "trash")
                }
            } label: {
                moreActionsIcon
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .help("More actions")

            Spacer(minLength: 0)

            Text(MessageRowPresentationSupport.timestampText(for: timestamp))
                .font(.caption2)
                .foregroundStyle(JinSemanticColor.textTertiary)
                .lineLimit(1)
        }
        // Align footer leading with the bubble's inner content rail
        // (bubble has .padding(JinSpacing.medium); footer lives outside, so
        // we mirror that padding here for a single-rail layout).
        .padding(.horizontal, JinSpacing.medium)
    }

    private var userFooter: some View {
        HStack(spacing: JinSpacing.small) {
            if isEditingUserMessage {
                actionIconButton(systemName: "xmark", helpText: "Cancel editing") {
                    onCancelUserEdit()
                }

                actionIconButton(systemName: "paperplane", helpText: "Resend") {
                    onSubmitUserEdit(itemID)
                }
            } else {
                Spacer(minLength: 0)

                if showsCopyButton {
                    CopyToPasteboardButton(text: copyText, helpText: "Copy message", useProminentStyle: false)
                        .accessibilityLabel("Copy message")
                }

                actionIconButton(systemName: "arrow.clockwise", helpText: "Regenerate") {
                    onRegenerate(itemID)
                }

                if canEditUserMessage {
                    actionIconButton(systemName: "pencil", helpText: "Edit") {
                        onEditUserMessage(itemID)
                    }
                }

                Menu {
                    Button(role: .destructive) {
                        requestDelete(.message)
                    } label: {
                        deleteActionMenuLabel("Delete message", systemImage: "trash")
                    }

                    if canDeleteResponse {
                        Button(role: .destructive) {
                            requestDelete(.response)
                        } label: {
                            deleteActionMenuLabel("Delete response", systemImage: "text.badge.minus")
                        }
                    }
                } label: {
                    moreActionsIcon
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20)
                .help("More actions")
            }
        }
        .padding(.horizontal, JinSpacing.medium)
    }

    @ViewBuilder
    private var speechControls: some View {
        let speechPresentation = MessageRowPresentationSupport.TextToSpeechPresentation(
            copyText: copyText,
            isConfigured: textToSpeechConfigured,
            isGenerating: textToSpeechIsGenerating,
            isPlaying: textToSpeechIsPlaying,
            isPaused: textToSpeechIsPaused
        )

        Button {
            onToggleSpeakAssistantMessage(itemID, copyText)
        } label: {
            if textToSpeechIsGenerating {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: speechPresentation.primarySystemName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }
        }
        .buttonStyle(.plain)
        .help(speechPresentation.helpText)
        .disabled(speechPresentation.isPrimaryDisabled)

        if speechPresentation.isActive {
            actionIconButton(systemName: "stop.circle", helpText: speechPresentation.stopHelpText) {
                onStopSpeakAssistantMessage(itemID)
            }
        }
    }

    private var moreActionsIcon: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
    }

    private func actionIconButton(systemName: String, helpText: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func deleteActionMenuLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .frame(width: 14, alignment: .center)
        }
    }

    private func requestDelete(_ action: DeleteAction) {
        pendingDeleteAction = action
        showingDeleteConfirmation = true
    }

    private func performPendingDelete() {
        switch pendingDeleteAction {
        case .message:
            onDeleteMessage(itemID)
        case .response:
            onDeleteResponse(itemID)
        case .none:
            break
        }
        pendingDeleteAction = nil
    }
}
