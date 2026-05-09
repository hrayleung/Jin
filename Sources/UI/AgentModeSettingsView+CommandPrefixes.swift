import SwiftUI

extension AgentModeSettingsView {
    var safePrefixesSection: some View {
        JinSettingsSection(
            "Safe Commands",
            detail: "Auto-approved when RTK can rewrite them."
        ) {
            DisclosureGroup("Safe commands (\(safePrefixes.count))") {
                FlowLayout(spacing: 4) {
                    ForEach(safePrefixes, id: \.self) { prefix in
                        AgentModeCommandPrefixChip(prefix) {
                            removeSafePrefix(prefix)
                        }
                    }
                }
                .padding(.top, JinSpacing.xSmall)

                JinSettingsControlRow(
                    "Add safe prefix",
                    supportingText: "Matches command start, e.g., python3."
                ) {
                    AgentModeCommandPrefixAddRow(
                        title: "Add safe prefix",
                        prompt: "e.g., python3",
                        text: $newSafePrefix
                    ) {
                        addSafePrefix()
                    }
                }
                .padding(.top, JinSpacing.xSmall)

                if AgentModeCommandPrefixSupport.shouldShowResetToDefaults(
                    currentPrefixes: safePrefixes,
                    defaultPrefixes: AgentCommandAllowlist.builtinDefaults
                ) {
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

    var allowedPrefixesSection: some View {
        JinSettingsSection("Additional Allowed Prefixes") {
            if allowedPrefixes.isEmpty {
                Text("No custom prefixes added.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 4) {
                    ForEach(allowedPrefixes, id: \.self) { prefix in
                        AgentModeCommandPrefixChip(prefix) {
                            removePrefix(prefix)
                        }
                    }
                }
            }

            JinSettingsControlRow(
                "Add prefix",
                supportingText: "Full prefix to auto-approve, e.g., npm run."
            ) {
                AgentModeCommandPrefixAddRow(
                    title: "Add prefix",
                    prompt: "e.g., npm run",
                    text: $newPrefix
                ) {
                    addPrefix()
                }
            }
        }
    }
}

private struct AgentModeCommandPrefixChip: View {
    let prefix: String
    let onRemove: () -> Void

    init(_ prefix: String, onRemove: @escaping () -> Void) {
        self.prefix = prefix
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(prefix)
                .font(.system(.caption, design: .monospaced))

            Button {
                onRemove()
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

private struct AgentModeCommandPrefixAddRow: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            TextField(title, text: $text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit {
                    onAdd()
                }

            Button("Add") {
                onAdd()
            }
            .buttonStyle(.bordered)
            .disabled(!AgentModeCommandPrefixSupport.canAddPrefix(text))
        }
    }
}

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
