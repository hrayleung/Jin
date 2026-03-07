import Foundation
import Darwin

struct CodexManagedProcessSnapshot: Equatable {
    let pid: Int32
    let parentPID: Int32
    let commandLine: String
}

enum CodexManagedProcessSupport {
    static let managedEnvironmentKey = "JIN_MANAGED_CODEX_APP_SERVER"
    static let managedEnvironmentValue = "1"
    private static let managedEnvironmentMarker = "\(managedEnvironmentKey)=\(managedEnvironmentValue)"
    private static let commandNeedle = "codex app-server"

    static func currentProcessSnapshots() -> [CodexManagedProcessSnapshot] {
        guard let raw = try? readProcessSnapshotOutput() else { return [] }
        return parseProcessSnapshot(raw)
    }

    static func parseProcessSnapshot(_ raw: String) -> [CodexManagedProcessSnapshot] {
        raw
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }

                let scanner = Scanner(string: trimmed)
                scanner.charactersToBeSkipped = .whitespaces

                guard let pidInt = scanner.scanInt(),
                      let parentInt = scanner.scanInt() else {
                    return nil
                }

                let commandStart = trimmed.index(trimmed.startIndex, offsetBy: scanner.currentIndex.utf16Offset(in: trimmed))
                let command = trimmed[commandStart...].trimmingCharacters(in: .whitespaces)
                guard !command.isEmpty else { return nil }

                return CodexManagedProcessSnapshot(
                    pid: Int32(pidInt),
                    parentPID: Int32(parentInt),
                    commandLine: command
                )
            }
    }

    static func managedRootPIDs(in snapshots: [CodexManagedProcessSnapshot]) -> Set<Int32> {
        Set(
            snapshots
                .filter { isManagedCodexAppServerCommand($0.commandLine) }
                .map(\.pid)
        )
    }

    static func shutdownOrder(
        for rootPIDs: Set<Int32>,
        snapshots: [CodexManagedProcessSnapshot]
    ) -> [Int32] {
        guard !rootPIDs.isEmpty else { return [] }

        let childrenByParent = Dictionary(grouping: snapshots, by: \.parentPID)
        var visited = Set<Int32>()
        var ordered: [Int32] = []

        func visit(_ pid: Int32) {
            guard visited.insert(pid).inserted else { return }
            let children = (childrenByParent[pid] ?? [])
                .map(\.pid)
                .sorted()
            for childPID in children {
                visit(childPID)
            }
            ordered.append(pid)
        }

        for rootPID in rootPIDs.sorted() {
            visit(rootPID)
        }

        return ordered
    }

    static func alivePIDs(in pids: [Int32]) -> [Int32] {
        pids.filter(isProcessAlive)
    }

    static func isProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    static func signal(_ pids: [Int32], signal: Int32) {
        for pid in pids where pid > 0 {
            _ = Darwin.kill(pid, signal)
        }
    }

    static func waitForExit(of pids: [Int32], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if alivePIDs(in: pids).isEmpty {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return alivePIDs(in: pids).isEmpty
    }

    static func isManagedCodexAppServerCommand(_ commandLine: String) -> Bool {
        commandLine.contains(managedEnvironmentMarker)
            && commandLine.localizedCaseInsensitiveContains(commandNeedle)
    }

    private static func readProcessSnapshotOutput() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["eww", "-ax", "-o", "pid=", "-o", "ppid=", "-o", "command="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "CodexManagedProcessSupport",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to read process list from ps."]
            )
        }
        return output
    }
}
