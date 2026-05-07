import SwiftUI

struct DataSettingsTotalStorageRow: View {
    let totalBytes: Int64

    var body: some View {
        HStack {
            Label {
                Text("Total")
                    .fontWeight(.medium)
            } icon: {
                Image(systemName: "externaldrive")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(DataSettingsFormatting.formattedSize(totalBytes))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .fontWeight(.medium)
        }
    }
}

struct DataSettingsStorageCategoryRow: View {
    let snapshot: StorageCategorySnapshot
    let totalBytes: Int64
    let onReveal: (StorageCategorySnapshot) -> Void
    let onRequestClear: (StorageCategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            HStack {
                Label {
                    Text(snapshot.category.label)
                } icon: {
                    Image(systemName: snapshot.category.systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }

                Spacer()

                Text(DataSettingsFormatting.formattedSize(snapshot.byteCount))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: JinSpacing.small) {
                Text(snapshot.category.description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer(minLength: JinSpacing.small)

                if snapshot.url != nil {
                    Button {
                        onReveal(snapshot)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Show in Finder")
                }

                if snapshot.category.isClearable {
                    Button {
                        onRequestClear(snapshot.category)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(snapshot.byteCount > 0 ? Color.red.opacity(0.8) : Color.secondary.opacity(0.4))
                    .disabled(snapshot.byteCount == 0)
                    .help(snapshot.byteCount > 0 ? "Clear \(snapshot.category.label)" : "Nothing to clear")
                }
            }

            if totalBytes > 0 && snapshot.byteCount > 0 {
                DataSettingsStorageBar(fraction: Double(snapshot.byteCount) / Double(totalBytes))
            }
        }
        .padding(.vertical, JinSpacing.xSmall)
    }
}

private struct DataSettingsStorageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(JinSemanticColor.subtleSurface)
                    .frame(height: 3)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: max(3, geometry.size.width * fraction), height: 3)
            }
        }
        .frame(height: 3)
    }
}
