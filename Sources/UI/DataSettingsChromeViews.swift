import SwiftUI

struct DataSettingsStorageSection: View {
    let totalBytes: Int64
    let isCalculating: Bool
    let onRecalculate: () -> Void

    var body: some View {
        JinSettingsSection("Storage") {
            storageDescription
            totalHeaderRow
            DataSettingsTotalStorageRow(totalBytes: totalBytes)
        }
    }

    private var storageDescription: some View {
        Text("Storage used by Jin on this Mac.")
            .jinInfoCallout()
    }

    private var totalHeaderRow: some View {
        HStack {
            Text("Total")
                .font(.subheadline.weight(.semibold))

            Spacer()

            recalculateControl
        }
    }

    @ViewBuilder
    private var recalculateControl: some View {
        if isCalculating {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        } else {
            Button {
                onRecalculate()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Recalculate storage sizes")
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
        if snapshots.isEmpty && !isCalculating {
            emptyState
        } else {
            snapshotRows
        }
    }

    private var emptyState: some View {
        Text("Calculating...")
            .foregroundStyle(.tertiary)
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
            if snapshot.id != snapshots.last?.id {
                Divider()
            }
        }
    }
}

struct DataSettingsChatsSection: View {
    let chatCount: Int
    let onRequestDeleteAllChats: () -> Void

    var body: some View {
        JinSettingsSection("Chats") {
            chatCountRow
            deleteAllChatsButton
        }
    }

    private var chatCountRow: some View {
        LabeledContent("Total Chats") {
            Text("\(chatCount)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var deleteAllChatsButton: some View {
        Button(role: .destructive) {
            onRequestDeleteAllChats()
        } label: {
            Label("Delete All Chats", systemImage: "trash")
        }
    }
}

struct DataSettingsRecoverySection: View {
    let exportStatusMessage: String?
    let importStatusMessage: String?
    let onExportRecoveryPack: () -> Void
    let onImportRecoveryPack: () -> Void

    var body: some View {
        JinSettingsSection("Recovery") {
            exportRecoveryButton
            importRecoveryButton
            recoveryStatusMessages
        }
    }

    private var exportRecoveryButton: some View {
        Button {
            onExportRecoveryPack()
        } label: {
            Label("Export Recovery Pack", systemImage: "square.and.arrow.up")
        }
    }

    private var importRecoveryButton: some View {
        Button {
            onImportRecoveryPack()
        } label: {
            Label("Import Recovery Pack", systemImage: "square.and.arrow.down")
        }
    }

    @ViewBuilder
    private var recoveryStatusMessages: some View {
        if let exportStatusMessage {
            recoveryStatusText(exportStatusMessage)
        }

        if let importStatusMessage {
            recoveryStatusText(importStatusMessage)
        }
    }

    private func recoveryStatusText(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
