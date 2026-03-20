import Foundation

enum AgentWorkingDirectorySupport {
    enum ValidationState: Equatable {
        case empty
        case valid(String)
        case missing(String)
        case notDirectory(String)

        var message: String {
            switch self {
            case .empty:
                return "No default working directory. Agent tools use the process default or explicit per-call cwd."
            case .valid(let path):
                return path
            case .missing(let path):
                return "Directory not found: \(path)"
            case .notDirectory(let path):
                return "Path is not a directory: \(path)"
            }
        }

        var isError: Bool {
            switch self {
            case .missing, .notDirectory:
                return true
            case .empty, .valid:
                return false
            }
        }
    }

    static func normalizedPath(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return (trimmed as NSString).expandingTildeInPath
    }

    static func validationState(for raw: String, fileManager: FileManager = .default) -> ValidationState {
        let normalized = normalizedPath(from: raw)
        guard !normalized.isEmpty else { return .empty }

        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: normalized, isDirectory: &isDirectory)
        guard exists else {
            return .missing(normalized)
        }
        guard isDirectory.boolValue else {
            return .notDirectory(normalized)
        }
        return .valid(normalized)
    }
}
