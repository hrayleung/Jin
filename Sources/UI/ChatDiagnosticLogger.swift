import Foundation

actor ChatDiagnosticLogger {
    static let shared = ChatDiagnosticLogger()

    private let sessionID = UUID().uuidString
    private let sessionStartedAt = Date()
    private let isoFormatter = ISO8601DateFormatter()
    private var activeLogFileURL: URL?

    nonisolated static var logRootDirectoryURL: URL {
        (try? AppDataLocations.chatDiagnosticsDirectoryURL())
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(AppDataLocations.sharedDirectoryName)/Logs/chat-diagnostics")
    }

    static var isLoggingEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKeys.chatDiagnosticLoggingEnabled)
    }

    private init() {
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    nonisolated static func log(
        runId: String,
        hypothesisId: String,
        message: String,
        data: [String: String] = [:],
        fileID: String = #fileID,
        line: Int = #line
    ) {
        guard isLoggingEnabled else { return }
        let location = "\(fileID):\(line)"
        let emittedAt = Date()
        Task.detached(priority: .utility) {
            await shared.append(
                runId: runId,
                hypothesisId: hypothesisId,
                location: location,
                message: message,
                data: data,
                emittedAt: emittedAt
            )
        }
    }

    func clearLogs() throws {
        let root = Self.logRootDirectoryURL
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        activeLogFileURL = nil
    }

    private func append(
        runId: String,
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String],
        emittedAt: Date
    ) {
        guard Self.isLoggingEnabled else { return }

        let payload: [String: Any] = [
            "sessionId": sessionID,
            "runId": runId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(emittedAt.timeIntervalSince1970 * 1000),
            "sessionStartedAt": isoFormatter.string(from: sessionStartedAt),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "appBuild": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let encoded = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }

        do {
            let fileURL = try resolvedLogFileURL()
            let parentDirectory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parentDirectory,
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: encoded)
            try handle.write(contentsOf: Data([0x0A]))
        } catch {
            // Keep logging failure silent to avoid affecting normal request flow.
        }
    }

    private func resolvedLogFileURL() throws -> URL {
        if let activeLogFileURL {
            return activeLogFileURL
        }

        let sessionDirectory = Self.logRootDirectoryURL
            .appendingPathComponent(Self.timeFolderComponent(for: sessionStartedAt), isDirectory: true)
        let fileURL = sessionDirectory
            .appendingPathComponent("\(Self.safePathComponent(sessionID)).ndjson", isDirectory: false)
        activeLogFileURL = fileURL
        return fileURL
    }

    private nonisolated static func timeFolderComponent(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: date)
    }

    private nonisolated static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let normalized = String(scalars)
        return normalized.isEmpty ? "_empty" : normalized
    }
}
