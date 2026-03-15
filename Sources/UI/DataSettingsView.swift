import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct DataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var conversations: [ConversationEntity]

    @State private var snapshots: [StorageCategorySnapshot] = []
    @State private var isCalculating = false
    @State private var showingDeleteAllChatsConfirmation = false
    @State private var categoryPendingClear: StorageCategory?
    @State private var showingClearConfirmation = false
    @State private var clearError: String?

    private let calculator = StorageSizeCalculator()

    private var totalBytes: Int64 {
        snapshots.reduce(0) { $0 + $1.byteCount }
    }

    var body: some View {
        Form {
            Section {
                Text("Storage used by Jin on this Mac.")
                    .jinInfoCallout()

                totalStorageRow
            } header: {
                HStack {
                    Text("Storage")
                    Spacer()
                    if isCalculating {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    } else {
                        Button {
                            recalculate()
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

            Section("Breakdown") {
                if snapshots.isEmpty && !isCalculating {
                    Text("Calculating...")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(snapshots) { snapshot in
                        storageCategoryRow(snapshot)
                    }
                }
            }

            Section("Chats") {
                LabeledContent("Total Chats") {
                    Text("\(conversations.count)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    showingDeleteAllChatsConfirmation = true
                } label: {
                    Label("Delete All Chats", systemImage: "trash")
                }
            }

            Section {
                Button {
                    openDataDirectory()
                } label: {
                    Label("Show Jin Data in Finder", systemImage: "folder")
                }
            } header: {
                Text("Quick Access")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .task {
            if snapshots.isEmpty {
                recalculate()
            }
        }
        .confirmationDialog("Delete all chats?", isPresented: $showingDeleteAllChatsConfirmation) {
            Button("Delete All Chats", role: .destructive) {
                deleteAllChats()
            }
        } message: {
            Text("This will permanently delete all \(conversations.count) chat\(conversations.count == 1 ? "" : "s") across all assistants. This cannot be undone.")
        }
        .confirmationDialog(
            clearConfirmationTitle,
            isPresented: $showingClearConfirmation,
            presenting: categoryPendingClear
        ) { category in
            Button("Clear \(category.label)", role: .destructive) {
                clearCategory(category)
            }
        } message: { category in
            Text(clearConfirmationMessage(for: category))
        }
        .alert("Clear Failed", isPresented: .init(
            get: { clearError != nil },
            set: { if !$0 { clearError = nil } }
        )) {
            Button("OK") { clearError = nil }
        } message: {
            if let clearError {
                Text(clearError)
            }
        }
    }

    // MARK: - Total Storage Row

    private var totalStorageRow: some View {
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

            Text(formattedSize(totalBytes))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .fontWeight(.medium)
        }
    }

    // MARK: - Category Row

    private func storageCategoryRow(_ snapshot: StorageCategorySnapshot) -> some View {
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

                Text(formattedSize(snapshot.byteCount))
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
                        showInFinder(snapshot)
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
                        categoryPendingClear = snapshot.category
                        showingClearConfirmation = true
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
                storageBar(fraction: Double(snapshot.byteCount) / Double(totalBytes))
            }
        }
        .padding(.vertical, JinSpacing.xSmall)
    }

    // MARK: - Storage Bar

    private func storageBar(fraction: Double) -> some View {
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

    // MARK: - Confirmation Helpers

    private var clearConfirmationTitle: String {
        if let category = categoryPendingClear {
            return "Clear \(category.label)?"
        }
        return "Clear Data?"
    }

    private func clearConfirmationMessage(for category: StorageCategory) -> String {
        let snapshot = snapshots.first { $0.category == category }
        let sizeStr = formattedSize(snapshot?.byteCount ?? 0)

        switch category {
        case .attachments:
            return "This will delete all attachment files (\(sizeStr)). Chat messages will remain but embedded media will no longer display."
        case .networkLogs:
            return "This will delete all network debug trace files (\(sizeStr))."
        case .mcpData:
            return "This will delete all MCP server isolation directories (\(sizeStr)). They will be recreated as needed."
        case .speechModels:
            return "This will delete all downloaded on-device speech models (\(sizeStr)). They will need to be re-downloaded to use again."
        case .backups:
            return "This will delete all automatic database backups (\(sizeStr)). New backups will be created on next launch."
        case .database:
            return ""
        }
    }

    // MARK: - Actions

    private func recalculate() {
        isCalculating = true
        Task {
            let result = await calculator.calculateAll()
            await MainActor.run {
                snapshots = result
                isCalculating = false
            }
        }
    }

    private func clearCategory(_ category: StorageCategory) {
        Task {
            do {
                try await calculator.clearCategory(category)
                recalculate()
            } catch {
                await MainActor.run {
                    clearError = "Failed to clear \(category.label): \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteAllChats() {
        Task {
            await MainActor.run {
                for conversation in conversations {
                    modelContext.delete(conversation)
                }
                try? modelContext.save()
            }

            // Refresh sizes after deletion
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run { recalculate() }
        }
    }

    private func showInFinder(_ snapshot: StorageCategorySnapshot) {
        guard let url = snapshot.url else { return }

        if snapshot.category == .database {
            // Reveal the default.store file in Finder
            let storeFile = url.appendingPathComponent("default.store")
            if FileManager.default.fileExists(atPath: storeFile.path) {
                NSWorkspace.shared.activateFileViewerSelecting([storeFile])
                return
            }
        }

        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            let parent = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.path) {
                NSWorkspace.shared.open(parent)
            }
        }
    }

    private func openDataDirectory() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }

        let jinDir = appSupport.appendingPathComponent("Jin", isDirectory: true)

        if FileManager.default.fileExists(atPath: jinDir.path) {
            NSWorkspace.shared.open(jinDir)
        } else {
            NSWorkspace.shared.open(appSupport)
        }
    }

    // MARK: - Formatting

    private func formattedSize(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 bytes" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
