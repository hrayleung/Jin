import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AgentModePopoverView: View {
    @Binding var isActive: Bool
    @AppStorage(AppPreferenceKeys.agentModeBypassPermissions) private var bypassPermissions = false
    @AppStorage(AppPreferenceKeys.agentModeWorkingDirectory) private var storedWorkingDirectory = ""
    @State private var workingDirectoryDraft = ""

    private var workingDirectoryValidation: AgentWorkingDirectorySupport.ValidationState {
        AgentWorkingDirectorySupport.validationState(for: workingDirectoryDraft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            Divider()
                .padding(.horizontal, JinSpacing.medium)

            permissionsSection

            Divider()
                .padding(.horizontal, JinSpacing.medium)

            workingDirectorySection
        }
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .onAppear {
            syncDraftFromStorage()
        }
        .onChange(of: storedWorkingDirectory) { _, _ in
            syncDraftFromStorage()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: JinSpacing.small) {
            HStack(spacing: JinSpacing.xSmall) {
                Text("Agent Mode")
                    .font(.subheadline.weight(.medium))

                Text("Beta")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(JinSemanticColor.subtleSurface)
                    )
                    .overlay(
                        Capsule()
                            .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
                    )
            }

            Spacer(minLength: 0)

            Toggle(isOn: $isActive) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Execute shell commands, read/write files, and search your codebase locally.")
        }
        .padding(.horizontal, JinSpacing.large)
        .padding(.vertical, JinSpacing.medium)
    }

    // MARK: - Bypass Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            HStack(spacing: JinSpacing.small) {
                Text("Bypass permissions")
                    .font(.subheadline.weight(.medium))

                Spacer(minLength: 0)

                Toggle(isOn: $bypassPermissions) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Group {
                Text("Auto-approve and execute tools immediately. ")
                    .foregroundStyle(.secondary)
                + Text("Use with caution.")
                    .foregroundStyle(.orange)
            }
            .font(.caption)
        }
        .padding(.horizontal, JinSpacing.large)
        .padding(.vertical, JinSpacing.medium)
    }

    // MARK: - Working Directory

    private var workingDirectorySection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text("Working directory")
                .font(.subheadline.weight(.medium))

            HStack(spacing: JinSpacing.small) {
                TextField(
                    text: $workingDirectoryDraft,
                    prompt: Text("/Users/you/Projects/my-app")
                ) {
                    EmptyView()
                }
                .font(.system(.caption, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(.horizontal, JinSpacing.small)
                .padding(.vertical, JinSpacing.xSmall + 2)
                .background(
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .fill(JinSemanticColor.subtleSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .stroke(
                            workingDirectoryValidation.isError
                                ? Color.orange.opacity(0.55)
                                : JinSemanticColor.separator.opacity(0.45),
                            lineWidth: JinStrokeWidth.hairline
                        )
                )
                .onChange(of: workingDirectoryDraft) { _, newValue in
                    applyWorkingDirectory(newValue)
                }

                Button {
                    selectDirectory()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: JinControlMetrics.iconButtonHitSize, height: JinControlMetrics.iconButtonHitSize)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(workingDirectoryValidation.message)
                .font(.caption)
                .foregroundStyle(workingDirectoryValidation.isError ? Color.orange : .secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(.horizontal, JinSpacing.large)
        .padding(.vertical, JinSpacing.medium)
    }

    // MARK: - Actions

    private func selectDirectory() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose a working directory for agent mode"

        let currentWorkingDirectory = workingDirectoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentWorkingDirectory.isEmpty {
            let currentURL = URL(fileURLWithPath: currentWorkingDirectory, isDirectory: true)
            if FileManager.default.fileExists(atPath: currentURL.path) {
                panel.directoryURL = currentURL
            }
        }

        if panel.runModal() == .OK, let url = panel.url {
            applyWorkingDirectory(url.path)
            workingDirectoryDraft = url.path
        }
        #endif
    }

    private func syncDraftFromStorage() {
        if workingDirectoryDraft != storedWorkingDirectory {
            workingDirectoryDraft = storedWorkingDirectory
        }
    }

    private func applyWorkingDirectory(_ value: String) {
        let normalized = AgentWorkingDirectorySupport.normalizedPath(from: value)
        if storedWorkingDirectory != normalized {
            storedWorkingDirectory = normalized
        }
    }
}
