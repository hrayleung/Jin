import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AgentModeSettingsView: View {
    @AppStorage(AppPreferenceKeys.agentModeEnabled) private var agentModeEnabled = false
    @AppStorage(AppPreferenceKeys.agentModeWorkingDirectory) private var workingDirectory = ""
    @AppStorage(AppPreferenceKeys.agentModeAllowedCommandPrefixesJSON) private var allowedPrefixesJSON = "[]"
    @AppStorage(AppPreferenceKeys.agentModeDefaultSafePrefixesJSON) private var safePrefixesJSON = ""
    @AppStorage(AppPreferenceKeys.agentModeCommandTimeoutSeconds) private var commandTimeoutSeconds = 120
    @AppStorage(AppPreferenceKeys.agentModeAutoApproveFileReads) private var autoApproveFileReads = true

    @State private var newPrefix = ""
    @State private var newSafePrefix = ""
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

    var body: some View {
        Form {
            Section {
                Toggle("Enable Agent Mode", isOn: $agentModeEnabled)
            } header: {
                Text("Agent Mode")
            } footer: {
                Text("Execute local shell commands, read/write files, and search codebases.")
            }

            if agentModeEnabled {
                workingDirectorySection

                toolTogglesSection

                safePrefixesSection

                allowedPrefixesSection

                safetySection
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .navigationTitle("Agent Mode")
    }

    // MARK: - Working Directory

    private var workingDirectorySection: some View {
        Section {
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
        } header: {
            Text("Working Directory")
        } footer: {
            Text("The default working directory for shell commands and file operations.")
        }
    }

    // MARK: - Tool Toggles

    private var toolTogglesSection: some View {
        Section("Enabled Tools") {
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

    // MARK: - Safe Command Prefixes

    private var safePrefixesSection: some View {
        Section {
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

                HStack(spacing: JinSpacing.small) {
                    TextField(
                        text: $newSafePrefix,
                        prompt: Text("e.g., python3")
                    ) {
                        EmptyView()
                    }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addSafePrefix()
                    }

                    Button("Add") {
                        addSafePrefix()
                    }
                    .buttonStyle(.bordered)
                    .disabled(newSafePrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        } header: {
            Text("Safe Commands")
        } footer: {
            Text("Commands starting with these prefixes are auto-approved without manual confirmation.")
        }
    }

    // MARK: - Custom Allowed Command Prefixes

    private var allowedPrefixesSection: some View {
        Section {
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
        } header: {
            Text("Additional Allowed Prefixes")
        } footer: {
            Text("Extra command prefixes to auto-approve, in addition to the safe commands above.")
        }
    }

    // MARK: - Safety Settings

    private var safetySection: some View {
        Section("Safety") {
            Toggle("Auto-approve file reads", isOn: $autoApproveFileReads)

            Text("When enabled, file read operations are executed without asking for approval.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("Command Timeout") {
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

            Text("Maximum time in seconds before a shell command is terminated.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
