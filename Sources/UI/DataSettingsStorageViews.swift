import SwiftUI

struct DataSettingsTotalStorageRow<Accessory: View>: View {
    let totalBytes: Int64
    private let accessory: () -> Accessory

    init(totalBytes: Int64, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.totalBytes = totalBytes
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
            Text("Used by Jin")

            Spacer(minLength: JinSpacing.small)

            Text(DataSettingsFormatting.formattedSize(totalBytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()

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
                    .fill(JinSemanticColor.controlFill)

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
        HStack(alignment: .center, spacing: JinSpacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
                Circle()
                    .fill(snapshot.category.chartColor)
                    .frame(width: 8, height: 8)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.category.label)
                    Text(snapshot.category.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: JinSpacing.small)

            sizeLabel
            actions
        }
        .padding(.vertical, 2)
    }

    private var sizeLabel: some View {
        Text(snapshot.byteCount > 0 ? DataSettingsFormatting.formattedSize(snapshot.byteCount) : "Empty")
            .foregroundStyle(snapshot.byteCount > 0 ? .secondary : .tertiary)
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityLabel(sizeAccessibilityLabel)
    }

    private var sizeAccessibilityLabel: String {
        let size = DataSettingsFormatting.formattedSize(snapshot.byteCount)
        guard let shareText else { return size }
        return "\(size), \(shareText) of total"
    }

    /// Both slots are always laid out so the size column lines up across rows
    /// whether or not a category can be cleared.
    private var actions: some View {
        HStack(spacing: JinSpacing.small) {
            Button("Show in Finder", systemImage: "folder") {
                onReveal(snapshot)
            }
            .help("Show in Finder")
            .opacity(snapshot.url == nil ? 0 : 1)
            .disabled(snapshot.url == nil)
            .accessibilityHidden(snapshot.url == nil)

            Button("Clear \(snapshot.category.label)", systemImage: "trash") {
                onRequestClear(snapshot.category)
            }
            .help(snapshot.byteCount > 0 ? "Clear \(snapshot.category.label)…" : "Nothing to clear")
            .opacity(snapshot.category.isClearable ? 1 : 0)
            .disabled(!snapshot.category.isClearable || snapshot.byteCount == 0)
            .accessibilityHidden(!snapshot.category.isClearable)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
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
