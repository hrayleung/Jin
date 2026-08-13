import SwiftUI

struct DataSettingsTotalStorageRow<Accessory: View>: View {
    let totalBytes: Int64
    private let accessory: () -> Accessory

    init(totalBytes: Int64, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.totalBytes = totalBytes
        self.accessory = accessory
    }

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

            accessory()
        }
    }
}

extension DataSettingsTotalStorageRow where Accessory == EmptyView {
    init(totalBytes: Int64) {
        self.init(totalBytes: totalBytes) { EmptyView() }
    }
}

/// macOS System Settings–style stacked bar: each segment is a storage category’s share of total.
struct DataSettingsCompositionBar: View {
    let snapshots: [StorageCategorySnapshot]
    let totalBytes: Int64

    private var segments: [(id: String, category: StorageCategory, fraction: Double)] {
        guard totalBytes > 0 else { return [] }
        return snapshots.compactMap { snapshot in
            let fraction = DataSettingsFormatting.shareFraction(
                bytes: snapshot.byteCount,
                total: totalBytes
            )
            guard fraction > 0 else { return nil }
            return (snapshot.id, snapshot.category, fraction)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(JinSemanticColor.subtleSurface)

                if !segments.isEmpty {
                    HStack(spacing: 1) {
                        ForEach(segments, id: \.id) { segment in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(segment.category.chartColor)
                                .frame(width: max(2, width * segment.fraction))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
        }
        .frame(height: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage breakdown")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard totalBytes > 0 else {
            return "No storage used"
        }
        let summary = snapshots.compactMap { snapshot -> String? in
            guard let share = DataSettingsFormatting.formattedShare(
                bytes: snapshot.byteCount,
                total: totalBytes
            ) else { return nil }
            return "\(snapshot.category.label) \(share)"
        }
        return summary.isEmpty ? "No storage used" : summary.joined(separator: ", ")
    }
}

struct DataSettingsStorageCategoryRow: View {
    let snapshot: StorageCategorySnapshot
    let totalBytes: Int64
    let onReveal: (StorageCategorySnapshot) -> Void
    let onRequestClear: (StorageCategory) -> Void

    private var shareText: String? {
        DataSettingsFormatting.formattedShare(bytes: snapshot.byteCount, total: totalBytes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            HStack {
                Label {
                    Text(snapshot.category.label)
                } icon: {
                    Image(systemName: snapshot.category.systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(snapshot.category.chartColor)
                        .frame(width: 16)
                }

                Spacer()

                sizeLabel
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
        }
        .padding(.vertical, JinSpacing.xSmall)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var sizeLabel: some View {
        HStack(spacing: 4) {
            Text(DataSettingsFormatting.formattedSize(snapshot.byteCount))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)

            if let shareText {
                Text("·")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Text(shareText)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

extension StorageCategory {
    /// Distinct chart color for the composition bar and breakdown list swatches.
    var chartColor: Color {
        switch self {
        case .attachments: return .blue
        case .database: return .purple
        case .networkLogs: return .orange
        case .chatDiagnostics: return .teal
        case .mcpData: return .green
        case .legacySpeechModels: return .gray
        }
    }
}
