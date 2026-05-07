import Foundation

struct RTKRuntimeStatus: Sendable {
    let helperURL: URL?
    let helperVersion: String?
    let configURL: URL?
    let teeDirectoryURL: URL?
    let errorDescription: String?
}

struct RTKExecutionOutput: Sendable {
    let text: String
    let exitCode: Int32
    let durationSeconds: Double
    let rawOutputPath: String?

    var isError: Bool {
        exitCode != 0
    }
}

enum RTKRuntimeError: LocalizedError {
    case missingHelper(expectedPath: String)
    case helperMisconfigured(path: String)
    case unsupportedCommand(String)
    case invalidRewriteOutput
    case configDirectoryUnavailable
    case configWriteFailed(String)
    case versionProbeFailed(exitCode: Int32, details: String)

    var errorDescription: String? {
        switch self {
        case .missingHelper(let expectedPath):
            return "Bundled RTK helper is unavailable at \(expectedPath). Repackage Jin before using Agent shell/search tools."
        case .helperMisconfigured(let path):
            return "RTK helper path is invalid: \(path)"
        case .unsupportedCommand(let command):
            return "RTK cannot rewrite this shell command: \(command). Use dedicated tools like file_read/grep_search/glob_search or switch to an RTK-supported command."
        case .invalidRewriteOutput:
            return "RTK returned an empty rewrite result."
        case .configDirectoryUnavailable:
            return "Unable to locate the RTK configuration directory."
        case .configWriteFailed(let message):
            return "Failed to manage RTK configuration: \(message)"
        case .versionProbeFailed(let exitCode, let details):
            return "RTK version probe failed (exit code: \(exitCode)). \(details)"
        }
    }
}
