import Foundation
import SwiftData
import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppLaunchCoordinator: ObservableObject {
    enum Phase {
        case starting
        case recovery(StartupRecoveryState)
        case ready(ModelContainer)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .starting

    private var startupTask: Task<Void, Never>?
    private var currentContainerCandidate: ModelContainer?

    func startIfNeeded() {
        guard startupTask == nil else { return }
        startupTask = Task { [weak self] in
            guard let self else { return }
            await self.performStartup()
        }
    }

    func continueWithCurrentState() {
        guard let currentContainerCandidate else { return }
        let counts = PersistenceContainerFactory.fetchCoreCounts(in: currentContainerCandidate)
        AppSnapshotManager.recordAcceptedCurrentState(counts)
        AppRuntimeProtection.automaticSnapshotsSuspended = false
        phase = .ready(currentContainerCandidate)
    }

    func restoreLatestHealthySnapshot() async {
        let snapshotResult = await Self.runInBackground {
            AppSnapshotManager.latestHealthySnapshot()
        }

        guard case .success(let snapshot) = snapshotResult, let snapshot else { return }
        await restoreSnapshot(snapshot)
    }

    func restoreSnapshot(_ snapshot: SnapshotSummary) async {
        let restoreResult = await Self.runInBackground {
            try AppSnapshotManager.restoreSnapshot(snapshot)
        }

        switch restoreResult {
        case .success:
            AppRuntimeProtection.automaticSnapshotsSuspended = false
            startupTask = nil
            await performStartup()
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        }
    }

    func importRecoveryArchive(from archiveURL: URL) async {
        let importResult = await Self.runInBackground {
            try AppSnapshotManager.queueImportArchiveForRestore(from: archiveURL)
        }

        switch importResult {
        case .success:
            AppRuntimeProtection.automaticSnapshotsSuspended = false
            startupTask = nil
            await performStartup()
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        }
    }

    private func performStartup() async {
        let startupResult = await Self.runInBackground {
            try AppSnapshotManager.evaluateCurrentStoreForStartup()
        }

        switch startupResult {
        case .success(let evaluation):
            switch evaluation {
            case .ready(let container):
                currentContainerCandidate = nil
                phase = .ready(container)
                captureStartupSnapshotInBackground()
            case .recovery(let recoveryState, let currentContainer):
                currentContainerCandidate = currentContainer
                AppRuntimeProtection.automaticSnapshotsSuspended = true
                phase = .recovery(recoveryState)
            }
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        }
    }

    private func captureStartupSnapshotInBackground() {
        guard !AppRuntimeProtection.automaticSnapshotsSuspended else { return }
        Task.detached(priority: .utility) {
            try? AppSnapshotManager.captureAutomaticSnapshot(reason: .launchHealthy)
        }
    }

    nonisolated private static func runInBackground<T>(
        _ operation: @escaping () throws -> T
    ) async -> Result<T, Error> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Result(catching: operation))
            }
        }
    }
}

struct AppRecoveryView: View {
    @ObservedObject var launchCoordinator: AppLaunchCoordinator
    let recoveryState: StartupRecoveryState

    @State private var importError: String?

    private var healthySnapshots: [SnapshotSummary] {
        recoveryState.snapshots.filter { $0.manifest.isHealthy }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                Text("Data Recovery Needed")
                    .font(.largeTitle.weight(.semibold))

                Text(recoveryState.issueDescription)
                    .foregroundStyle(.secondary)
            }

            if healthySnapshots.isEmpty {
                Text("No healthy snapshots are available right now. You can import a recovery pack or continue with the current state if Jin can still open it.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: JinSpacing.small) {
                    Text("Available Snapshots")
                        .font(.headline)

                    ScrollView {
                        VStack(alignment: .leading, spacing: JinSpacing.small) {
                            ForEach(healthySnapshots) { snapshot in
                                Button {
                                    Task { await launchCoordinator.restoreSnapshot(snapshot) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(snapshot.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.body.weight(.medium))
                                            Text(snapshotSummaryText(snapshot))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("Restore")
                                    }
                                    .padding(JinSpacing.medium)
                                    .background(
                                        RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                                            .fill(JinSemanticColor.surface)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            HStack(spacing: JinSpacing.medium) {
                if !healthySnapshots.isEmpty {
                    Button("Restore Latest Healthy Snapshot") {
                        Task { await launchCoordinator.restoreLatestHealthySnapshot() }
                    }
                }

                Button("Import Recovery Pack") {
                    importRecoveryPack()
                }

                if recoveryState.canContinueCurrentState {
                    Button("Continue with Current Data") {
                        launchCoordinator.continueWithCurrentState()
                    }
                }
            }

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(JinSemanticColor.detailSurface.ignoresSafeArea())
    }

    private func snapshotSummaryText(_ snapshot: SnapshotSummary) -> String {
        let counts = snapshot.manifest.counts
        return "\(counts.conversations) chats, \(counts.messages) messages, \(counts.providers) providers, \(counts.assistants) assistants, \(counts.mcpServers) MCP servers"
    }

    private func importRecoveryPack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [RecoveryPackType.type, .zip]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else {
            importError = nil
            return
        }

        Task {
            await launchCoordinator.importRecoveryArchive(from: url)
        }
    }
}

struct AppRootContentView<Content: View>: View {
    @ObservedObject var launchCoordinator: AppLaunchCoordinator
    let content: (ModelContainer) -> Content

    var body: some View {
        Group {
            switch launchCoordinator.phase {
            case .starting:
                VStack(spacing: JinSpacing.medium) {
                    ProgressView()
                    Text("Preparing Jin data…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(JinSemanticColor.detailSurface.ignoresSafeArea())

            case .recovery(let recoveryState):
                AppRecoveryView(launchCoordinator: launchCoordinator, recoveryState: recoveryState)

            case .ready(let container):
                content(container)

            case .failed(let message):
                VStack(alignment: .leading, spacing: JinSpacing.medium) {
                    Text("Jin Failed to Start")
                        .font(.title.weight(.semibold))
                    Text(message)
                        .foregroundStyle(.secondary)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(JinSemanticColor.detailSurface.ignoresSafeArea())
            }
        }
    }
}
