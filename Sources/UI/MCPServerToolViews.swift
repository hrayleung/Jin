import SwiftUI

struct MCPServerToolsSection: View {
    let verifying: Bool
    let hasTransportValidationError: Bool
    let verifyError: String?
    var verifyErrorDetails: String? = nil
    let tools: [MCPToolInfo]
    let isToolEnabled: (MCPToolInfo) -> Bool
    let onVerify: () -> Void
    let onHide: () -> Void
    let onSetToolEnabled: (MCPToolInfo, Bool) -> Void
    let onViewSchema: (MCPToolInfo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            verificationActions
            verificationError
            toolList
        }
        .animation(.easeInOut(duration: 0.18), value: verifyError)
        .animation(.easeInOut(duration: 0.18), value: tools.count)
    }

    private var verificationActions: some View {
        HStack(spacing: JinSpacing.medium) {
            Text(tools.isEmpty ? "Connect to see available tools." : toolCountSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: JinSpacing.small)

            Button {
                onVerify()
            } label: {
                HStack(spacing: 6) {
                    if verifying {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(tools.isEmpty ? "Check connection" : "Refresh tools")
                }
            }
            .fixedSize()
            .disabled(verifying || hasTransportValidationError)

            if !tools.isEmpty {
                Button("Hide") {
                    onHide()
                }
                .fixedSize()
                .disabled(verifying)
            }
        }
        .controlSize(.small)
    }

    private var toolCountSummary: String {
        tools.count == 1 ? "1 tool" : "\(tools.count) tools"
    }

    @ViewBuilder
    private var verificationError: some View {
        if let verifyError {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                Text(verifyError)
                    .textSelection(.enabled)
                    .jinInlineErrorText()

                if let verifyErrorDetails, !verifyErrorDetails.isEmpty {
                    DisclosureGroup("Connection details") {
                        VStack(alignment: .leading, spacing: JinSpacing.small) {
                            Text(verifyErrorDetails)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Copy details") {
                                PasteboardSupport.writeString(
                                    [verifyError, verifyErrorDetails].joined(separator: "\n\n")
                                )
                            }
                            .controlSize(.small)
                        }
                        .padding(.top, JinSpacing.small)
                    }
                    .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var toolList: some View {
        if !tools.isEmpty {
            LazyVStack(alignment: .leading, spacing: JinSpacing.medium) {
                ForEach(tools) { tool in
                    Divider()
                    MCPToolRowView(
                        tool: tool,
                        isEnabled: Binding(
                            get: { isToolEnabled(tool) },
                            set: { isEnabled in
                                onSetToolEnabled(tool, isEnabled)
                            }
                        ),
                        viewSchema: {
                            onViewSchema(tool)
                        }
                    )
                }
            }
        }
    }
}

struct MCPToolSchemaSheet: View {
    let tool: MCPToolInfo
    let onDone: () -> Void

    var body: some View {
        JinSheet(tool.displayName) {
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.large) {
                    if tool.displayName != tool.name || !tool.description.isEmpty {
                        VStack(alignment: .leading, spacing: JinSpacing.small) {
                            if tool.displayName != tool.name {
                                HStack(spacing: JinSpacing.small) {
                                    Text(tool.name)
                                        .font(.callout.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(tool.name)

                                    Spacer(minLength: 0)

                                    Button {
                                        PasteboardSupport.writeString(tool.name)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Copy tool ID")
                                    .accessibilityLabel("Copy tool ID")
                                }
                            }
                            if !tool.description.isEmpty {
                                Text(tool.description)
                                    .font(.body)
                                    .lineSpacing(2)
                            }
                        }
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: JinSpacing.small) {
                        Text("Input schema")
                            .font(.headline)
                        MCPToolSchemaPanelView(
                            text: formattedSchemaText(tool.inputSchema) ?? "No schema available.",
                            usesMonospacedFont: true
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        } actions: {
            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .onExitCommand(perform: onDone)
        .frame(minWidth: 520, minHeight: 420)
    }

    private func formattedSchemaText(_ schema: ParameterSchema) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(schema) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct MCPToolSchemaPanelView: View {
    let text: String
    var usesMonospacedFont = false

    var body: some View {
        Text(text)
            .font(usesMonospacedFont ? .system(.caption, design: .monospaced) : .caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(JinSpacing.medium)
            .jinSurface(.outlined, cornerRadius: JinRadius.medium)
    }
}

private struct MCPToolRowView: View {
    let tool: MCPToolInfo
    @Binding var isEnabled: Bool
    let viewSchema: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: JinSpacing.large) {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                    Text(tool.displayName)
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)

                    if tool.displayName != tool.name {
                        Text(tool.name)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .help(tool.name)
                    }
                }

                if !tool.description.isEmpty {
                    Text(tool.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: JinSpacing.small) {
                Toggle("Enable \(tool.displayName)", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Button("Details…", action: viewSchema)
                    .font(.callout)
                    .buttonStyle(.borderless)
                    .help("View full description and input schema")
                    .accessibilityLabel("Details for \(tool.displayName)")
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
