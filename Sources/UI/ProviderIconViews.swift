import SwiftUI

struct ProviderIconView: View {
    @Environment(\.colorScheme) private var colorScheme

    let iconID: String?
    var fallbackSystemName: String = "network"
    var size: CGFloat = 18

    var body: some View {
        if let iconImage {
            iconImage
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            fallbackIcon
        }
    }

    private var iconImage: Image? {
        guard let icon = LobeProviderIconCatalog.icon(forID: iconID),
              let nsImage = icon.localPNGImage(useDarkMode: colorScheme == .dark) else {
            return nil
        }
        return Image(nsImage: nsImage)
    }

    private var fallbackIcon: some View {
        Image(systemName: fallbackSystemName)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.8, height: size * 0.8)
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}

struct ProviderIconPickerField: View {
    @Binding var selectedIconID: String?
    let defaultIconID: String?

    @State private var isPickerPresented = false

    private var activeIconID: String? {
        let trimmed = selectedIconID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed?.isEmpty == false {
            return trimmed
        }
        return defaultIconID
    }

    var body: some View {
        HStack(alignment: .center, spacing: JinSpacing.medium) {
            Text("Icon")

            Spacer()

            Button {
                isPickerPresented = true
            } label: {
                HStack(spacing: JinSpacing.small) {
                    ProviderIconView(iconID: activeIconID, size: 18)
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
            .help("Choose provider icon")
            .sheet(isPresented: $isPickerPresented) {
                ProviderIconPickerSheet(selectedIconID: $selectedIconID, defaultIconID: defaultIconID)
            }
        }
    }

    private var iconLabel: String {
        if let selectedIconID {
            let trimmed = selectedIconID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let defaultIconID {
            return "Default (\(defaultIconID))"
        }

        return "Choose..."
    }
}

private struct ProviderIconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedIconID: String?
    let defaultIconID: String?

    @State private var searchText = ""
    @State private var draftIconID: String?

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 88), spacing: JinSpacing.medium)
    ]

    private var filteredIcons: [LobeProviderIcon] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return LobeProviderIconCatalog.all }

        return LobeProviderIconCatalog.all.filter { icon in
            icon.id.lowercased().contains(query) || icon.docsSlug.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: JinSpacing.medium) {
                TextField("Search provider icon", text: $searchText)
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
            .navigationTitle("Provider Icons")
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
        .frame(minWidth: 640, minHeight: 520)
        .onAppear {
            draftIconID = selectedIconID
        }
    }

    private var defaultCell: some View {
        let isSelected = draftIconID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false

        return Button {
            draftIconID = nil
        } label: {
            VStack(spacing: JinSpacing.xSmall) {
                ZStack(alignment: .bottomTrailing) {
                    ProviderIconView(iconID: defaultIconID, size: 26)
                        .frame(width: 40, height: 40)
                        .jinSurface(.subtle, cornerRadius: JinRadius.medium)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .font(.system(size: 13, weight: .bold))
                            .offset(x: 4, y: 4)
                    }
                }

                Text("Default")
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

    private func iconCell(icon: LobeProviderIcon) -> some View {
        let isSelected = draftIconID?.caseInsensitiveCompare(icon.id) == .orderedSame

        return Button {
            draftIconID = icon.id
        } label: {
            VStack(spacing: JinSpacing.xSmall) {
                ZStack(alignment: .bottomTrailing) {
                    ProviderIconView(iconID: icon.id, size: 26)
                        .frame(width: 40, height: 40)
                        .jinSurface(.subtle, cornerRadius: JinRadius.medium)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .font(.system(size: 13, weight: .bold))
                            .offset(x: 4, y: 4)
                    }
                }

                Text(icon.id)
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
}
