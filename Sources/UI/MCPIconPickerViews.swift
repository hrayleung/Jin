import SwiftUI

struct MCPIconPickerField: View {
    @Binding var selectedIconID: String?
    let defaultIconID: String

    @State private var isPickerPresented = false

    private var activeIconID: String {
        MCPIconPickerSupport.activeIconID(
            selectedIconID: selectedIconID,
            defaultIconID: defaultIconID
        )
    }

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: JinSpacing.small) {
                MCPIconView(iconID: activeIconID, size: 18)
                    .frame(width: 22, height: 22)
                    .jinSurface(.subtle, cornerRadius: JinRadius.small)

                Text(iconLabel)
                    .font(.body)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, JinSpacing.medium - 2)
            .padding(.vertical, JinSpacing.xSmall + 2)
            .jinSurface(.neutral, cornerRadius: JinRadius.small)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("MCP server icon"))
        .accessibilityValue(Text(iconLabel))
        .accessibilityHint(Text("Opens the MCP server icon picker"))
        .help("Choose MCP server icon")
        .sheet(isPresented: $isPickerPresented) {
            MCPIconPickerSheet(
                selectedIconID: $selectedIconID,
                defaultIconID: defaultIconID
            )
        }
    }

    private var iconLabel: String {
        MCPIconPickerSupport.displayLabel(
            selectedIconID: selectedIconID,
            defaultIconID: defaultIconID
        )
    }
}

private struct MCPIconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedIconID: String?
    let defaultIconID: String

    @State private var searchText = ""
    @State private var draftIconID: String?

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 88), spacing: JinSpacing.medium)
    ]

    private var filteredIcons: [MCPIcon] {
        MCPIconPickerSupport.filteredIcons(
            from: MCPIconCatalog.all,
            searchText: searchText,
            defaultIconID: defaultIconID
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: JinSpacing.medium) {
                TextField("Search MCP icon", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: JinSpacing.medium) {
                        defaultCell

                        ForEach(filteredIcons) { icon in
                            iconCell(icon: icon)
                        }
                    }
                    .padding(.vertical, JinSpacing.small)
                }
                .jinSurface(.raised, cornerRadius: JinRadius.medium)
            }
            .padding(JinSpacing.medium)
            .navigationTitle("MCP Icons")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selectedIconID = draftIconID
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 460)
        .onAppear {
            draftIconID = selectedIconID
        }
    }

    private var defaultCell: some View {
        let isSelected = MCPIconPickerSupport.isDefaultSelected(
            draftIconID,
            defaultIconID: defaultIconID
        )

        return MCPIconPickerIconCell(
            iconID: defaultIconID,
            title: "Default",
            isSelected: isSelected
        ) {
            draftIconID = nil
        }
    }

    private func iconCell(icon: MCPIcon) -> some View {
        let isSelected = MCPIconPickerSupport.isSelected(
            icon: icon,
            selectedIconID: draftIconID,
            defaultIconID: defaultIconID
        )

        return MCPIconPickerIconCell(
            iconID: icon.id,
            title: icon.id,
            isSelected: isSelected
        ) {
            draftIconID = icon.id
        }
    }
}

private struct MCPIconPickerIconCell: View {
    let iconID: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: JinSpacing.xSmall) {
                ZStack(alignment: .bottomTrailing) {
                    MCPIconView(iconID: iconID, size: 26)
                        .frame(width: 40, height: 40)
                        .jinSurface(.subtle, cornerRadius: JinRadius.medium)

                    if isSelected {
                        selectionIndicator
                    }
                }

                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, JinSpacing.small)
            .padding(.horizontal, JinSpacing.xSmall)
            .jinSurface(isSelected ? .selected : .neutral, cornerRadius: JinRadius.medium)
        }
        .buttonStyle(.plain)
    }

    private var selectionIndicator: some View {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.accentColor)
            .font(.system(size: 13, weight: .bold))
            .offset(x: 4, y: 4)
    }
}
