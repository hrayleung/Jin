import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers

struct DataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var conversations: [ConversationEntity]

    @State private var snapshots: [StorageCategorySnapshot] = []
    @State private var isCalculating = false
    @State private var showingDeleteAllChatsConfirmation = false
    @State private var categoryPendingClear: StorageCategory?
    @State private var showingClearConfirmation = false
    @State private var clearError: String?
    @State private var importStatusMessage: String?
    @State private var exportStatusMessage: String?

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

                Button {
                    exportRecoveryPack()
                } label: {
                    Label("Export Recovery Pack", systemImage: "square.and.arrow.up")
                }

                Button {
                    importRecoveryPack()
                } label: {
                    Label("Import Recovery Pack", systemImage: "square.and.arrow.down")
                }

                if let exportStatusMessage {
                    Text(exportStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let importStatusMessage {
                    Text(importStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Recovery")
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
                let counts = SnapshotCoreCounts(
                    conversations: (try? modelContext.fetchCount(FetchDescriptor<ConversationEntity>())) ?? 0,
                    messages: (try? modelContext.fetchCount(FetchDescriptor<MessageEntity>())) ?? 0,
                    providers: (try? modelContext.fetchCount(FetchDescriptor<ProviderConfigEntity>())) ?? 0,
                    assistants: (try? modelContext.fetchCount(FetchDescriptor<AssistantEntity>())) ?? 0,
                    mcpServers: (try? modelContext.fetchCount(FetchDescriptor<MCPServerConfigEntity>())) ?? 0
                )
                AppSnapshotManager.recordAcceptedCurrentState(counts)
            }

            // Refresh sizes after deletion
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run { recalculate() }
        }
    }

    private func showInFinder(_ snapshot: StorageCategorySnapshot) {
        guard let url = snapshot.url else { return }

        if snapshot.category == .database {
            let storeFile = url.appendingPathComponent(AppDataLocations.storeFileName)
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
        guard let dataRoot = try? AppDataLocations.rootDirectoryURL() else { return }

        if FileManager.default.fileExists(atPath: dataRoot.path) {
            NSWorkspace.shared.open(dataRoot)
        } else {
            NSWorkspace.shared.open(dataRoot.deletingLastPathComponent())
        }
    }

    private func exportRecoveryPack() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Jin-\(Self.recoveryPackDateFormatter.string(from: .now)).jinbackup"
        panel.allowedContentTypes = [RecoveryPackType.type]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportStatusMessage = "Exporting recovery pack…"

        Task.detached(priority: .userInitiated) {
            let result = Result { try AppSnapshotManager.exportRecoveryArchive(to: url) }
            await MainActor.run {
                switch result {
                case .success:
                    exportStatusMessage = "Exported recovery pack to \(url.lastPathComponent)."
                case .failure(let error):
                    exportStatusMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importRecoveryPack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [RecoveryPackType.type, .zip]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        importStatusMessage = "Validating and queuing recovery pack…"
        Task.detached(priority: .userInitiated) {
            let result = Result { try AppSnapshotManager.queueImportArchiveForRestore(from: url) }
            await MainActor.run {
                switch result {
                case .success:
                    importStatusMessage = "Recovery pack queued. Jin will restart to apply it."
                    Self.scheduleRelaunch()
                case .failure(let error):
                    importStatusMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private static func scheduleRelaunch() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1 && open \(Self.shellQuoted(bundlePath))"]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }

    private static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Formatting

    private static let recoveryPackDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func formattedSize(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 bytes" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
