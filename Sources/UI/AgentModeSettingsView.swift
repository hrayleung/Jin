import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AgentModeSettingsView: View {
    @AppStorage(AppPreferenceKeys.agentModeEnabled) private var agentModeEnabled = false
    @AppStorage(AppPreferenceKeys.agentModeWorkingDirectory) private var storedWorkingDirectory = ""
    @AppStorage(AppPreferenceKeys.agentModeAllowedCommandPrefixesJSON) private var allowedPrefixesJSON = "[]"
    @AppStorage(AppPreferenceKeys.agentModeDefaultSafePrefixesJSON) private var safePrefixesJSON = ""
    @AppStorage(AppPreferenceKeys.agentModeCommandTimeoutSeconds) private var commandTimeoutSeconds = 120
    @AppStorage(AppPreferenceKeys.agentModeAutoApproveFileReads) private var autoApproveFileReads = true

    @State private var newPrefix = ""
    @State private var newSafePrefix = ""
    @State private var rtkStatus: RTKRuntimeStatus?
    @State private var isRefreshingRTKStatus = false
    @State private var workingDirectoryDraft = ""
    @AppStorage(AppPreferenceKeys.agentModeToolShell) private var enableShell = true
    @AppStorage(AppPreferenceKeys.agentModeToolFileRead) private var enableFileRead = true
    @AppStorage(AppPreferenceKeys.agentModeToolFileWrite) private var enableFileWrite = true
    @AppStorage(AppPreferenceKeys.agentModeToolFileEdit) private var enableFileEdit = true
    @AppStorage(AppPreferenceKeys.agentModeToolGlob) private var enableGlob = true
    @AppStorage(AppPreferenceKeys.agentModeToolGrep) private var enableGrep = true

    private var allowedPrefixes: [String] {
        AppPreferences.decodeStringArrayJSON(allowedPrefixesJSON)
    }

    private var safePrefixes: [String] {
        if safePrefixesJSON.isEmpty {
            return AgentCommandAllowlist.builtinDefaults
        }
        return AppPreferences.decodeStringArrayJSON(safePrefixesJSON)
    }

    private var workingDirectoryValidation: AgentWorkingDirectorySupport.ValidationState {
        AgentWorkingDirectorySupport.validationState(for: workingDirectoryDraft)
    }

    var body: some View {
        JinSettingsPage {
            JinSettingsSection("Agent Mode") {
                Toggle("Enable Agent Mode", isOn: $agentModeEnabled)
            }

            if agentModeEnabled {
                workingDirectorySection

                toolTogglesSection

                rtkSection

                safePrefixesSection

                allowedPrefixesSection

                safetySection

                detailsSection
            }
        }
        .navigationTitle("Agent Mode")
        .onAppear {
            syncWorkingDirectoryDraft()
        }
        .onChange(of: storedWorkingDirectory) { _, _ in
            syncWorkingDirectoryDraft()
        }
        .task(id: agentModeEnabled) {
            guard agentModeEnabled else { return }
            await refreshRTKStatus()
        }
    }

    // MARK: - Working Directory

    private var workingDirectorySection: some View {
        JinSettingsSection(
            "Working Directory",
            detail: "Choose the folder Agent Mode can read, search, and edit."
        ) {
            JinSettingsControlRow("Path") {
                VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                    HStack(spacing: JinSpacing.small) {
                        TextField(
                            "Working Directory",
                            text: $workingDirectoryDraft,
                            prompt: Text("e.g., /Users/you/Projects/my-app")
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: workingDirectoryDraft) { _, newValue in
                            applyWorkingDirectory(newValue)
                        }

                        Button("Browse") {
                            selectDirectory()
                        }
                        .buttonStyle(.bordered)
                        .help("Choose a working directory for Agent Mode.")
                    }

                    Text(workingDirectoryValidation.message)
                        .font(.caption)
                        .foregroundStyle(workingDirectoryValidation.isError ? Color.orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Tool Toggles

    private var toolTogglesSection: some View {
        JinSettingsSection("Enabled Tools") {
            Toggle(isOn: $enableShell) {
                Label("Shell Execute", systemImage: "terminal")
            }
            Toggle(isOn: $enableFileRead) {
                Label("File Read", systemImage: "doc.text")
            }
            Toggle(isOn: $enableFileWrite) {
                Label("File Write", systemImage: "square.and.pencil")
            }
            Toggle(isOn: $enableFileEdit) {
                Label("File Edit", systemImage: "pencil.line")
            }
            Toggle(isOn: $enableGlob) {
                Label("Glob Search", systemImage: "doc.text.magnifyingglass")
            }
            Toggle(isOn: $enableGrep) {
                Label("Grep Search", systemImage: "magnifyingglass")
            }
        }
    }

    // MARK: - RTK Status

    private var rtkSection: some View {
        JinSettingsSection(
            "Bundled RTK",
            detail: "RTK handles shell, grep, and glob execution for Agent Mode."
        ) {
            if let status = rtkStatus {
                JinSettingsControlRow("Version", controlAlignment: .trailing) {
                    Text(status.helperVersion ?? "Unavailable")
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                JinSettingsControlRow("Helper Path", controlAlignment: .trailing) {
                    Text(status.helperURL?.path ?? "Missing")
                        .font(.system(.caption, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                JinSettingsControlRow("RTK Config", controlAlignment: .trailing) {
                    if let configURL = status.configURL {
                        Text(configURL.path)
                            .font(.system(.caption, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Text("Unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                JinSettingsControlRow("Tee Directory", controlAlignment: .trailing) {
                    if let teeDirectoryURL = status.teeDirectoryURL {
                        Text(teeDirectoryURL.path)
                            .font(.system(.caption, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Text("Unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

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

    // MARK: - Safe Command Prefixes

    private var safePrefixesSection: some View {
        JinSettingsSection(
            "Safe Commands",
            detail: "Commands starting with these prefixes are auto-approved when RTK can rewrite them."
        ) {
            DisclosureGroup("Safe commands (\(safePrefixes.count))") {
                FlowLayout(spacing: 4) {
                    ForEach(safePrefixes, id: \.self) { prefix in
                        HStack(spacing: 4) {
                            Text(prefix)
                                .font(.system(.caption, design: .monospaced))

                            Button {
                                removeSafePrefix(prefix)
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
                .padding(.top, JinSpacing.xSmall)

                JinSettingsControlRow(
                    "Add safe prefix",
                    supportingText: "Matches the beginning of a command, for example python3."
                ) {
                    HStack(spacing: JinSpacing.small) {
                        TextField(
                            "Add safe prefix",
                            text: $newSafePrefix,
                            prompt: Text("e.g., python3")
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            addSafePrefix()
                        }

                        Button("Add") {
                            addSafePrefix()
                        }
                        .buttonStyle(.bordered)
                        .disabled(newSafePrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.top, JinSpacing.xSmall)

                if safePrefixes != AgentCommandAllowlist.builtinDefaults {
                    Button("Reset to Defaults") {
                        safePrefixesJSON = AppPreferences.encodeStringArrayJSON(AgentCommandAllowlist.builtinDefaults)
                    }
                    .font(.caption)
                    .padding(.top, JinSpacing.xSmall)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Custom Allowed Command Prefixes

    private var allowedPrefixesSection: some View {
        JinSettingsSection(
            "Additional Allowed Prefixes",
            detail: "Extend the auto-approved list with prefixes that make sense for your workflow."
        ) {
            if allowedPrefixes.isEmpty {
                Text("No custom prefixes added.")
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

            JinSettingsControlRow(
                "Add prefix",
                supportingText: "Use the full prefix you want auto-approved, for example npm run."
            ) {
                HStack(spacing: JinSpacing.small) {
                    TextField(
                        "Add prefix",
                        text: $newPrefix,
                        prompt: Text("e.g., npm run")
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
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
        }
    }

    // MARK: - Safety Settings

    private var safetySection: some View {
        JinSettingsSection("Safety") {
            JinSettingsControlRow(
                "Auto-approve file reads",
                supportingText: "Skips approval prompts for read-only file access."
            ) {
                Toggle("Auto-approve file reads", isOn: $autoApproveFileReads)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            JinSettingsControlRow(
                "Command Timeout",
                supportingText: "Maximum shell runtime before Jin terminates the command."
            ) {
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

    private var detailsSection: some View {
        JinSettingsSection("Details") {
            JinDetailsDisclosure(title: "How Agent Mode Works") {
                Text("Agent Mode can run shell commands, search codebases, and edit local files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Shell, grep, and glob run through RTK. File reads and edits stay local.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            JinDetailsDisclosure(title: "Approval Rules") {
                Text("Safe commands are auto-approved by prefix, but RTK still rejects commands it cannot rewrite.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Additional allowed prefixes extend that auto-approval list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Auto-approve file reads skips approval prompts for reads only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            JinDetailsDisclosure(title: "RTK") {
                Text("Agent shell commands must be rewriteable by RTK.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Jin manages RTK tee output so you can reopen the full raw logs later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Command timeout is the maximum runtime before a shell command is terminated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

        let normalizedWorkingDirectory = AgentWorkingDirectorySupport.normalizedPath(from: workingDirectoryDraft)
        if !normalizedWorkingDirectory.isEmpty {
            let currentDir = URL(fileURLWithPath: normalizedWorkingDirectory, isDirectory: true)
            if FileManager.default.fileExists(atPath: currentDir.path) {
                panel.directoryURL = currentDir
            }
        }

        if panel.runModal() == .OK, let url = panel.url {
            applyWorkingDirectory(url.path)
            workingDirectoryDraft = url.path
        }
        #endif
    }

    private func syncWorkingDirectoryDraft() {
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

    private func addSafePrefix() {
        let trimmed = newSafePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var prefixes = safePrefixes
        if !prefixes.contains(trimmed) {
            prefixes.append(trimmed)
            safePrefixesJSON = AppPreferences.encodeStringArrayJSON(prefixes)
        }
        newSafePrefix = ""
    }

    private func removeSafePrefix(_ prefix: String) {
        var prefixes = safePrefixes
        prefixes.removeAll { $0 == prefix }
        safePrefixesJSON = AppPreferences.encodeStringArrayJSON(prefixes)
    }

    @MainActor
    private func refreshRTKStatus() async {
        guard !isRefreshingRTKStatus else { return }
        isRefreshingRTKStatus = true
        defer { isRefreshingRTKStatus = false }
        let status = await RTKRuntimeSupport.status()
        rtkStatus = status
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
