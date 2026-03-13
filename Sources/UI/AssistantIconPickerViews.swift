import SwiftUI

struct AssistantIconPickerButton: View {
    @Binding var selectedIcon: String
    @State private var isPickerPresented = false

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: JinSpacing.small) {
                iconPreview
                    .frame(width: JinControlMetrics.iconButtonHitSize, height: JinControlMetrics.iconButtonHitSize)
                    .jinSurface(.selected, cornerRadius: JinRadius.small)

                Text(selectedIcon.isEmpty ? "Choose Icon\u{2026}" : "Change Icon")
                    .font(.body)
                    .foregroundStyle(.secondary)
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
        .sheet(isPresented: $isPickerPresented) {
            AssistantIconPickerSheet(selectedIcon: $selectedIcon)
        }
    }

    private var iconPreview: some View {
        Group {
            let trimmed = selectedIcon.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: JinControlMetrics.assistantGlyphSize, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else if trimmed.count <= 2 {
                Text(trimmed)
                    .font(.system(size: JinControlMetrics.assistantGlyphSize))
            } else {
                Image(systemName: trimmed)
                    .font(.system(size: JinControlMetrics.assistantGlyphSize, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

struct AssistantIconCategory: Identifiable {
    let id = UUID()
    let name: String
    let icons: [String]
}

struct AssistantIconPickerSheet: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var draftIcon = ""

    let iconOptions: [AssistantIconCategory] = [
        AssistantIconCategory(
            name: "Characters",
            icons: ["person.crop.circle", "person.fill", "person.2.fill", "figure.wave", "sparkles", "star.fill", "heart.fill", "face.smiling", "crown.fill", "moon.stars.fill"]
        ),
        AssistantIconCategory(
            name: "Technology",
            icons: ["laptopcomputer", "desktopcomputer", "iphone", "applewatch", "brain", "cpu", "antenna.radiowaves.left.and.right", "waveform", "bolt.fill", "lightbulb.fill"]
        ),
        AssistantIconCategory(
            name: "Communication",
            icons: ["bubble.left.and.bubble.right", "message.fill", "envelope.fill", "phone.fill", "video.fill", "mic.fill", "speaker.wave.3.fill", "quote.bubble", "megaphone.fill", "bell.fill"]
        ),
        AssistantIconCategory(
            name: "Creative",
            icons: ["paintbrush.fill", "pencil", "pencil.and.outline", "book.fill", "doc.text.fill", "photo.fill", "music.note", "film", "camera.fill", "theatermasks.fill"]
        ),
        AssistantIconCategory(
            name: "Business",
            icons: ["briefcase.fill", "chart.line.uptrend.xyaxis", "dollarsign.circle.fill", "building.2.fill", "cart.fill", "creditcard.fill", "paperplane.fill", "folder.fill", "calendar", "clock.fill"]
        ),
        AssistantIconCategory(
            name: "Science",
            icons: ["graduationcap.fill", "atom", "flask.fill", "testtube.2", "leaf.fill", "globe", "pawprint.fill", "dna", "fossil.shell.fill", "mountain.2.fill"]
        ),
        AssistantIconCategory(
            name: "Emoji & Custom",
            icons: ["\u{1F916}", "\u{1F3A8}", "\u{1F4A1}", "\u{1F680}", "\u{26A1}\u{FE0F}", "\u{1F3AF}", "\u{1F525}", "\u{2728}", "\u{1F31F}", "\u{1F4AB}"]
        )
    ]

    var filteredCategories: [AssistantIconCategory] {
        if searchText.isEmpty {
            return iconOptions
        }

        return iconOptions.compactMap { category in
            let filtered = category.icons.filter { icon in
                icon.localizedCaseInsensitiveContains(searchText)
            }
            return filtered.isEmpty ? nil : AssistantIconCategory(name: category.name, icons: filtered)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if searchText.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("None")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            Button {
                                draftIcon = ""
                            } label: {
                                HStack(spacing: JinSpacing.small) {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, height: 44)
                                        .jinSurface(draftIcon.isEmpty ? .selected : .neutral, cornerRadius: JinRadius.medium)

                                    Text("No Icon")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .jinSurface(.raised, cornerRadius: JinRadius.medium)
                    }

                    ForEach(filteredCategories) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.name)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                                ForEach(category.icons, id: \.self) { icon in
                                    AssistantIconButton(
                                        icon: icon,
                                        isSelected: draftIcon == icon
                                    ) {
                                        draftIcon = icon
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .jinSurface(.raised, cornerRadius: JinRadius.medium)
                    }
                }
                .padding(20)
            }
            .background(JinSemanticColor.detailSurface)
            .navigationTitle("Choose Icon")
            .searchable(text: $searchText, prompt: "Search icons...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selectedIcon = draftIcon
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .onAppear {
            draftIcon = selectedIcon
        }
    }
}

struct AssistantIconButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            iconView
                .frame(width: 44, height: 44)
                .jinSurface(isSelected ? .selected : .neutral, cornerRadius: JinRadius.medium)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconView: some View {
        if icon.count <= 2 {
            Text(icon)
                .font(.system(size: 24))
        } else {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
    }
}
