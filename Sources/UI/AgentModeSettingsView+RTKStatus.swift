import SwiftUI

#if os(macOS)
import AppKit
#endif

extension AgentModeSettingsView {
    var rtkSection: some View {
        JinSettingsSection(
            "Bundled RTK",
            detail: "RTK handles shell, grep, and glob execution for Agent Mode."
        ) {
            if let status = rtkStatus {
                AgentModeRTKStatusRow("Version", value: status.helperVersion)
                AgentModeRTKStatusRow("Helper Path", value: status.helperURL?.path ?? "Missing", isSelectable: true)
                AgentModeRTKStatusRow("RTK Config", value: status.configURL?.path, isSelectable: true)
                AgentModeRTKStatusRow("Tee Directory", value: status.teeDirectoryURL?.path, isSelectable: true)

                if let errorDescription = status.errorDescription {
                    Text(errorDescription)
                        .jinInlineErrorText()
                }
            } else if isRefreshingRTKStatus {
                HStack(spacing: JinSpacing.small) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking RTK helper…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("RTK status unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: JinSpacing.small) {
                Button("Refresh Status") {
                    Task { await refreshRTKStatus() }
                }
                .buttonStyle(.bordered)
                .help("Refresh the bundled RTK status.")

                if let configURL = rtkStatus?.configURL,
                   FileManager.default.fileExists(atPath: configURL.path) {
                    Button("Open Config") {
                        NSWorkspace.shared.open(configURL)
                    }
                    .buttonStyle(.bordered)
                    .help("Open the RTK config file in Finder.")
                }

                if let teeDirectoryURL = rtkStatus?.teeDirectoryURL {
                    Button("Reveal Tee Directory") {
                        NSWorkspace.shared.activateFileViewerSelecting([teeDirectoryURL])
                    }
                    .buttonStyle(.bordered)
                    .help("Reveal the RTK tee output directory in Finder.")
                }
            }
        }
    }
}

private struct AgentModeRTKStatusRow: View {
    private let title: String
    private let value: String?
    private let missingValue: String
    private let isSelectable: Bool

    init(
        _ title: String,
        value: String?,
        missingValue: String = "Unavailable",
        isSelectable: Bool = false
    ) {
        self.title = title
        self.value = value
        self.missingValue = missingValue
        self.isSelectable = isSelectable
    }

    var body: some View {
        JinSettingsControlRow(title, controlAlignment: .trailing) {
            statusText
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if let value, isSelectable {
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else if let value {
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else if isSelectable {
            Text(missingValue)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Text(missingValue)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
