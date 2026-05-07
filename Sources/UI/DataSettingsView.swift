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
        DataSettingsSupport.totalBytes(in: snapshots)
    }

    var body: some View {
        JinSettingsPage {
            DataSettingsStorageSection(
                totalBytes: totalBytes,
                isCalculating: isCalculating,
                onRecalculate: recalculate
            )

            DataSettingsBreakdownSection(
                snapshots: snapshots,
                totalBytes: totalBytes,
                isCalculating: isCalculating,
                onReveal: showInFinder,
                onRequestClear: requestClear
            )

            DataSettingsChatsSection(
                chatCount: conversations.count,
                onRequestDeleteAllChats: { showingDeleteAllChatsConfirmation = true }
            )

            DataSettingsRecoverySection(
                exportStatusMessage: exportStatusMessage,
                importStatusMessage: importStatusMessage,
                onExportRecoveryPack: exportRecoveryPack,
                onImportRecoveryPack: importRecoveryPack
            )
        }
        .navigationTitle("Data")
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
            Text(DataSettingsSupport.deleteAllChatsConfirmationMessage(chatCount: conversations.count))
        }
        .confirmationDialog(
            DataSettingsSupport.clearConfirmationTitle(category: categoryPendingClear),
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

    // MARK: - Actions

    private func requestClear(_ category: StorageCategory) {
        categoryPendingClear = category
        showingClearConfirmation = true
    }

    private func clearConfirmationMessage(for category: StorageCategory) -> String {
        let byteCount = snapshots.first { $0.category == category }?.byteCount ?? 0
        return DataSettingsSupport.clearConfirmationMessage(for: category, byteCount: byteCount)
    }

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

    private func exportRecoveryPack() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = DataSettingsSupport.recoveryPackFilename(for: .now)
        panel.allowedContentTypes = [RecoveryPackType.type]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportStatusMessage = DataSettingsSupport.exportStartedMessage

        Task.detached(priority: .userInitiated) {
            let result = Result { try AppSnapshotManager.exportRecoveryArchive(to: url) }
            await MainActor.run {
                switch result {
                case .success:
                    exportStatusMessage = DataSettingsSupport.exportSuccessMessage(fileName: url.lastPathComponent)
                case .failure(let error):
                    exportStatusMessage = DataSettingsSupport.exportFailureMessage(errorDescription: error.localizedDescription)
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

        importStatusMessage = DataSettingsSupport.importStartedMessage
        Task.detached(priority: .userInitiated) {
            let result = Result { try AppSnapshotManager.queueImportArchiveForRestore(from: url) }
            await MainActor.run {
                switch result {
                case .success:
                    importStatusMessage = DataSettingsSupport.importSuccessMessage
                    Self.scheduleRelaunch()
                case .failure(let error):
                    importStatusMessage = DataSettingsSupport.importFailureMessage(errorDescription: error.localizedDescription)
                }
            }
        }
    }

    private static func scheduleRelaunch() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1 && open \(DataSettingsSupport.shellQuoted(bundlePath))"]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }
}
