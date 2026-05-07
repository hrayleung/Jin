import SwiftUI

struct PluginCredentialActionsView: View {
    let canTestConnection: Bool
    let canClear: Bool
    let isTesting: Bool
    var showsProgress: Bool? = nil
    let statusMessage: String?
    let statusIsError: Bool
    var spacing: CGFloat = JinSpacing.medium
    let onTestConnection: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            actionRow
            statusText
        }
    }

    private var actionRow: some View {
        HStack(spacing: spacing) {
            testConnectionButton
            clearButton
            Spacer()
            progressIndicator
        }
    }

    private var testConnectionButton: some View {
        Button("Test Connection") {
            onTestConnection()
        }
        .disabled(!canTestConnection || isTesting)
    }

    private var clearButton: some View {
        Button("Clear", role: .destructive) {
            onClear()
        }
        .disabled(!canClear || isTesting)
    }

    @ViewBuilder
    private var progressIndicator: some View {
        if showsProgress ?? isTesting {
            ProgressView()
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if let statusMessage {
            JinSettingsStatusText(
                text: statusMessage,
                isError: statusIsError,
                isSuccess: JinSettingsStatusText.isConnectionVerifiedStatus(
                    statusMessage,
                    isError: statusIsError
                )
            )
        }
    }
}
