import SwiftUI

struct DataSettingsStorageSection: View {
    let totalBytes: Int64
    let snapshots: [StorageCategorySnapshot]
    let isCalculating: Bool
    let onRecalculate: () -> Void

    var body: some View {
        JinSettingsSection("Storage") {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                DataSettingsTotalStorageRow(totalBytes: totalBytes) {
                    recalculateControl
                }
                DataSettingsCompositionBar(snapshots: snapshots, totalBytes: totalBytes)
            }
            .padding(.vertical, JinSpacing.xSmall)
        }
    }

    @ViewBuilder
    private var recalculateControl: some View {
        if isCalculating {
            ProgressView()
                .controlSize(.small)
        } else {
            Button("Recalculate", systemImage: "arrow.clockwise", action: onRecalculate)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Recalculate storage")
        }
    }
}

struct DataSettingsBreakdownSection: View {
    let snapshots: [StorageCategorySnapshot]
    let totalBytes: Int64
    let isCalculating: Bool
    let onReveal: (StorageCategorySnapshot) -> Void
    let onRequestClear: (StorageCategory) -> Void

    var body: some View {
        JinSettingsSection("Breakdown") {
            breakdownContent
        }
    }

    @ViewBuilder
    private var breakdownContent: some View {
        if snapshots.isEmpty {
            emptyState
        } else {
            snapshotRows
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            if isCalculating { ProgressView().controlSize(.small) }
            Text(isCalculating ? "Calculating…" : "Storage details are unavailable.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var snapshotRows: some View {
        ForEach(snapshots) { snapshot in
            DataSettingsStorageCategoryRow(
                snapshot: snapshot,
                totalBytes: totalBytes,
                onReveal: onReveal,
                onRequestClear: onRequestClear
            )
        }
    }
}

struct DataSettingsChatsSection: View {
    let chatCount: Int
    let onRequestDeleteAllChats: () -> Void

    var body: some View {
        JinSettingsSection("Chats") {
            JinSettingsControlRow("All chats") {
                HStack(spacing: JinSpacing.medium) {
                    Text(chatCount.formatted())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Button("Delete All…", role: .destructive, action: onRequestDeleteAllChats)
                        .controlSize(.small)
                        .disabled(chatCount == 0)
                }
            }
        }
    }
}

struct DataSettingsRecoverySection: View {
    let exportStatusMessage: String?
    let importStatusMessage: String?
    let onExportRecoveryPack: () -> Void
    let onImportRecoveryPack: () -> Void

    var body: some View {
        JinSettingsSection("Recovery Pack") {
            JinSettingsControlRow(
                "Export",
                supportingText: exportStatusMessage ?? "Save your chats, assistants, and settings to a single file."
            ) {
                Button("Export…", action: onExportRecoveryPack)
                    .controlSize(.small)
            }

            JinSettingsControlRow(
                "Import",
                supportingText: importStatusMessage ?? "Replace the data on this Mac with a recovery pack. Jin restarts to apply it."
            ) {
                Button("Import…", action: onImportRecoveryPack)
                    .controlSize(.small)
            }
        }
    }
}
