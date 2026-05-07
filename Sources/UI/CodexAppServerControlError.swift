import Foundation

enum CodexAppServerControlError: LocalizedError {
    case invalidListenURL(String)
    case alreadyRunning
    case executableNotFound(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidListenURL(let message):
            return message
        case .alreadyRunning:
            return "codex app-server is already running."
        case .executableNotFound(let message):
            return message
        case .launchFailed(let message):
            return message
        }
    }
}
