import Foundation
import SwiftData

enum SnapshotReason: String, Codable, Sendable {
    case launchHealthy
    case periodic
    case termination
    case manualExport
    case beforeDestructiveAction
    case importedArchive
    case legacyImport
}

struct SnapshotCoreCounts: Codable, Equatable, Sendable {
    let conversations: Int
    let messages: Int
    let providers: Int
    let assistants: Int
    let mcpServers: Int

    var total: Int {
        conversations + messages + providers + assistants + mcpServers
    }

    var isEmpty: Bool {
        total == 0
    }

    var isSeedLike: Bool {
        conversations == 0
            && messages == 0
            && assistants <= 1
            && providers <= DefaultProviderSeeds.allProviders().count
            && mcpServers <= 2
    }
}

struct SnapshotManifest: Codable, Identifiable, Sendable {
    var id: String
    var createdAt: Date
    var reason: SnapshotReason
    var appVersion: String
    var schemaVersion: Int
    var includesSecrets: Bool
    var isAutomatic: Bool
    var isHealthy: Bool
    var isLegacy: Bool
    var integrityDetail: String
    var counts: SnapshotCoreCounts
    var hasAttachments: Bool
    var hasPreferences: Bool
    var note: String?
}

struct SnapshotSummary: Identifiable, Sendable {
    let manifest: SnapshotManifest
    let directoryURL: URL

    var id: String { manifest.id }
}

struct StartupRecoveryState: Sendable {
    let issueDescription: String
    let snapshots: [SnapshotSummary]
    let canContinueCurrentState: Bool
}

enum StartupStoreEvaluation {
    case ready(ModelContainer)
    case recovery(StartupRecoveryState, ModelContainer?)
}

enum SnapshotError: LocalizedError {
    case invalidSnapshot(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSnapshot(let message), .exportFailed(let message):
            return message
        }
    }
}

private final class LockedRuntimeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    var current: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}

enum AppRuntimeProtection {
    private static let automaticSnapshotsSuspendedFlag = LockedRuntimeFlag(false)

    static var automaticSnapshotsSuspended: Bool {
        get { automaticSnapshotsSuspendedFlag.current }
        set { automaticSnapshotsSuspendedFlag.current = newValue }
    }
}
