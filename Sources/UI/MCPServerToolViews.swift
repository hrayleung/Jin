import SwiftUI

struct MCPServerToolsSection: View {
    let verifying: Bool
    let hasTransportValidationError: Bool
    let verifyError: String?
    let tools: [MCPToolInfo]
    let isToolEnabled: (MCPToolInfo) -> Bool
    let onVerify: () -> Void
    let onHide: () -> Void
    let onSetToolEnabled: (MCPToolInfo, Bool) -> Void
    let onViewSchema: (MCPToolInfo) -> Void

    var body: some View {
        JinSettingsSection(
            "Tools",
            detail: "Verify the server to inspect and selectively disable tools.",
            style: .plain
        ) {
            VStack(alignment: .leading, spacing: 8) {
                verificationActions
                verificationError
                toolGrid
            }
            .animation(.easeInOut(duration: 0.18), value: verifyError)
            .animation(.easeInOut(duration: 0.18), value: tools.count)
        }
    }

    private var verificationActions: some View {
        HStack {
            Button {
                onVerify()
            } label: {
                HStack {
                    Text("Verify (View Tools)")
                    if verifying {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
            .disabled(verifying || hasTransportValidationError)

            Spacer()

            if !tools.isEmpty {
                Button("Hide") {
                    onHide()
                }
                .disabled(verifying)
            }
        }
    }

    @ViewBuilder
    private var verificationError: some View {
        if let verifyError {
            Text(verifyError)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .jinInlineErrorText()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var toolGrid: some View {
        if !tools.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240), spacing: 12, alignment: .topLeading)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(tools) { tool in
                    MCPToolCardView(
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
            .padding(.top, 8)
        }
    }
}

struct MCPToolSchemaSheet: View {
    let tool: MCPToolInfo
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                if let schemaText = formattedSchemaText(tool.inputSchema) {
                    MCPToolSchemaPanelView(text: schemaText, usesMonospacedFont: true)
                } else {
                    MCPToolSchemaPanelView(text: "No schema available.")
                }
            }
            .background(JinSemanticColor.detailSurface)
            .navigationTitle(tool.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { onDone() }
                }
            }
        }
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
            .padding(JinSpacing.medium)
            .jinSurface(.outlined, cornerRadius: JinRadius.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MCPToolCardView: View {
    let tool: MCPToolInfo
    @Binding var isEnabled: Bool
    let viewSchema: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text(tool.name)
                .font(.headline)

            if !tool.description.isEmpty {
                Text(tool.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            Button("\u{2026} View Input Schema") {
                viewSchema()
            }
            .font(.caption)
            .buttonStyle(.link)

            Toggle("Enable", isOn: $isEnabled)
                .toggleStyle(.checkbox)
        }
        .padding(JinSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jinSurface(.outlined, cornerRadius: JinRadius.medium)
    }
}
