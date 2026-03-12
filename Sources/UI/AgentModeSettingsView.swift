import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AgentModeSettingsView: View {
    @AppStorage(AppPreferenceKeys.agentModeEnabled) private var agentModeEnabled = false
    @AppStorage(AppPreferenceKeys.agentModeWorkingDirectory) private var workingDirectory = ""
    @AppStorage(AppPreferenceKeys.agentModeAllowedCommandPrefixesJSON) private var allowedPrefixesJSON = "[]"
    @AppStorage(AppPreferenceKeys.agentModeCommandTimeoutSeconds) private var commandTimeoutSeconds = 120
    @AppStorage(AppPreferenceKeys.agentModeAutoApproveFileReads) private var autoApproveFileReads = true

    @State private var newPrefix = ""
    @AppStorage(AppPreferenceKeys.agentModeToolShell) private var enableShell = true
    @AppStorage(AppPreferenceKeys.agentModeToolFileRead) private var enableFileRead = true
    @AppStorage(AppPreferenceKeys.agentModeToolFileWrite) private var enableFileWrite = true
    @AppStorage(AppPreferenceKeys.agentModeToolFileEdit) private var enableFileEdit = true
    @AppStorage(AppPreferenceKeys.agentModeToolGlob) private var enableGlob = true
    @AppStorage(AppPreferenceKeys.agentModeToolGrep) private var enableGrep = true

    private var allowedPrefixes: [String] {
        AppPreferences.decodeStringArrayJSON(allowedPrefixesJSON)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JinSpacing.large) {
                // Header
                VStack(alignment: .leading, spacing: JinSpacing.small) {
                    Text("Agent Mode")
                        .font(.title2.weight(.semibold))
                    Text("Execute local shell commands, read/write files, and search codebases. The agent can interact with your local development environment.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Enable Toggle
                Toggle("Enable Agent Mode", isOn: $agentModeEnabled)
                    .toggleStyle(.switch)

                if agentModeEnabled {
                    Divider()

                    // Working Directory
                    workingDirectorySection

                    Divider()

                    // Tool Toggles
                    toolTogglesSection

                    Divider()

                    // Allowed Command Prefixes
                    allowedPrefixesSection

                    Divider()

                    // Safety Settings
                    safetySection
                }
            }
            .padding(JinSpacing.large)
        }
        .background {
            JinSemanticColor.detailSurface
                .ignoresSafeArea()
        }
    }

    // MARK: - Working Directory

    private var workingDirectorySection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text("Working Directory")
                .font(.headline)
            Text("The default working directory for shell commands and file operations.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: JinSpacing.small) {
                TextField(
                    text: $workingDirectory,
                    prompt: Text("e.g., /Users/you/Projects/my-app")
                ) {
                    EmptyView()
                }
                .textFieldStyle(.roundedBorder)

                Button("Browse") {
                    selectDirectory()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Tool Toggles

    private var toolTogglesSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text("Enabled Tools")
                .font(.headline)
            Text("Choose which tools the agent can use.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: JinSpacing.small) {
                toolToggle("Shell Execute", systemImage: "terminal", isOn: $enableShell, description: "Run shell commands")
                toolToggle("File Read", systemImage: "doc.text", isOn: $enableFileRead, description: "Read file contents")
                toolToggle("File Write", systemImage: "pencil.line", isOn: $enableFileWrite, description: "Create and write files")
                toolToggle("File Edit", systemImage: "pencil.line", isOn: $enableFileEdit, description: "Find and replace in files")
                toolToggle("Glob Search", systemImage: "doc.text.magnifyingglass", isOn: $enableGlob, description: "Find files by pattern")
                toolToggle("Grep Search", systemImage: "magnifyingglass", isOn: $enableGrep, description: "Search file contents")
            }
            .padding(JinSpacing.medium)
            .jinSurface(.raised, cornerRadius: JinRadius.large)
        }
    }

    private func toolToggle(_ title: String, systemImage: String, isOn: Binding<Bool>, description: String) -> some View {
        HStack(spacing: JinSpacing.small) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Allowed Command Prefixes

    private var allowedPrefixesSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text("Allowed Command Prefixes")
                .font(.headline)
            Text("Shell commands starting with these prefixes will be auto-approved without asking. All other commands require manual approval.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: JinSpacing.small) {
                // Default prefixes info
                DisclosureGroup("Default safe prefixes (\(AgentCommandAllowlist.defaultSafePrefixes.count))") {
                    FlowLayout(spacing: 4) {
                        ForEach(AgentCommandAllowlist.defaultSafePrefixes, id: \.self) { prefix in
                            Text(prefix)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .jinSurface(.subtle, cornerRadius: JinRadius.small)
                        }
                    }
                    .padding(.top, JinSpacing.xSmall)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                // Custom prefixes
                Text("Custom Prefixes")
                    .font(.subheadline.weight(.medium))

                if allowedPrefixes.isEmpty {
                    Text("No custom prefixes added. Default safe prefixes are always active.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    FlowLayout(spacing: 4) {
                        ForEach(allowedPrefixes, id: \.self) { prefix in
                            HStack(spacing: 4) {
                                Text(prefix)
                                    .font(.system(.caption, design: .monospaced))

                                Button {
                                    removePrefix(prefix)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .jinSurface(.subtle, cornerRadius: JinRadius.small)
                        }
                    }
                }

                HStack(spacing: JinSpacing.small) {
                    TextField(
                        text: $newPrefix,
                        prompt: Text("e.g., npm run")
                    ) {
                        EmptyView()
                    }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addPrefix()
                    }

                    Button("Add") {
                        addPrefix()
                    }
                    .buttonStyle(.bordered)
                    .disabled(newPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(JinSpacing.medium)
            .jinSurface(.raised, cornerRadius: JinRadius.large)
        }
    }

    // MARK: - Safety Settings

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text("Safety")
                .font(.headline)

            Toggle("Auto-approve file reads", isOn: $autoApproveFileReads)
                .toggleStyle(.switch)

            Text("When enabled, file read operations are executed without asking for approval.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: JinSpacing.small) {
                Text("Command Timeout")
                    .font(.subheadline.weight(.medium))
                Text("Maximum time in seconds before a shell command is terminated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: JinSpacing.small) {
                    Slider(
                        value: Binding(
                            get: { Double(commandTimeoutSeconds) },
                            set: { commandTimeoutSeconds = Int($0) }
                        ),
                        in: 30...600,
                        step: 30
                    )
                    Text("\(commandTimeoutSeconds)s")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 45, alignment: .trailing)
                }
            }
        }
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

        if let currentDir = URL(string: workingDirectory), FileManager.default.fileExists(atPath: currentDir.path) {
            panel.directoryURL = currentDir
        }

        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
        #endif
    }

    private func addPrefix() {
        let trimmed = newPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var prefixes = allowedPrefixes
        if !prefixes.contains(trimmed) {
            prefixes.append(trimmed)
            allowedPrefixesJSON = AppPreferences.encodeStringArrayJSON(prefixes)
        }
        newPrefix = ""
    }

    private func removePrefix(_ prefix: String) {
        var prefixes = allowedPrefixes
        prefixes.removeAll { $0 == prefix }
        allowedPrefixesJSON = AppPreferences.encodeStringArrayJSON(prefixes)
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, containerWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, containerWidth: bounds.width).offsets

        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + offsets[index].x, y: bounds.minY + offsets[index].y),
                proposal: .unspecified
            )
        }
    }

    private func layout(sizes: [CGSize], containerWidth: CGFloat) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for size in sizes {
            if x + size.width > containerWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (offsets, CGSize(width: maxWidth, height: y + rowHeight))
    }
}
