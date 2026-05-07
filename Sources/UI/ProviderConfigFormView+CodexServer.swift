import SwiftUI

extension ProviderConfigFormView {
    var codexServerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let presentation = codexServerStatusPresentation
            let buttonState = codexServerButtonState

            HStack(spacing: 6) {
                Circle()
                    .fill(presentation.tone.color)
                    .frame(width: 8, height: 8)
                Text(presentation.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(presentation.message)
                .foregroundStyle(.secondary)

            if let codexServerLaunchError {
                JinSettingsErrorText(text: codexServerLaunchError)
            } else if let lastLine = codexServerController.lastOutputLine, !lastLine.isEmpty {
                Text(lastLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lingeringProcessWarning = CodexAppServerFormSupport.lingeringProcessWarning(
                status: codexServerController.status,
                managedProcessCount: codexServerController.managedProcessCount
            ) {
                Text(lingeringProcessWarning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button {
                    startCodexServer()
                } label: {
                    Label("Start Server", systemImage: "play.fill")
                }
                .buttonStyle(.borderless)
                .disabled(buttonState.startDisabled)

                Button {
                    stopCodexServer()
                } label: {
                    Label("Stop Server", systemImage: "stop.fill")
                }
                .buttonStyle(.borderless)
                .disabled(buttonState.stopDisabled)

                Button(role: .destructive) {
                    forceStopCodexServer()
                } label: {
                    Label("Force Stop", systemImage: "bolt.slash.fill")
                }
                .buttonStyle(.borderless)
                .disabled(buttonState.forceStopDisabled)

                Button {
                    codexServerController.refreshManagedProcesses()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh Jin-managed Codex process status")
            }
        }
        .padding(.vertical, 4)
    }

    var codexServerListenURL: String {
        CodexAppServerFormSupport.listenURL(baseURL: provider.baseURL)
    }

    var codexServerListenURLValidationError: String? {
        CodexAppServerFormSupport.listenURLValidationError(codexServerListenURL)
    }

    var codexServerStatusPresentation: CodexAppServerFormSupport.StatusPresentation {
        CodexAppServerFormSupport.statusPresentation(
            status: codexServerController.status,
            listenURL: codexServerListenURL,
            validationError: codexServerListenURLValidationError
        )
    }

    var codexServerButtonState: CodexAppServerFormSupport.ButtonState {
        CodexAppServerFormSupport.buttonState(
            status: codexServerController.status,
            hasManagedProcesses: codexServerController.hasManagedProcesses,
            validationError: codexServerListenURLValidationError
        )
    }

    func startCodexServer() {
        codexServerLaunchError = nil

        if let validation = codexServerListenURLValidationError {
            codexServerLaunchError = validation
            return
        }

        do {
            try codexServerController.start(listenURL: codexServerListenURL)
        } catch {
            codexServerLaunchError = error.localizedDescription
        }
    }

    func stopCodexServer() {
        codexServerLaunchError = nil
        codexServerController.stop()
    }

    func forceStopCodexServer() {
        codexServerLaunchError = nil
        codexServerController.forceStopManagedServers()
    }
}
