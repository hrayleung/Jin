import Foundation

enum RTKRuntimeSupport {
    static let embeddedVersion = "0.31.0"
}

extension RTKRuntimeSupport {
    static func failureDetails(stdout: String, stderr: String) -> String {
        if let stderrText = stderr.trimmedNonEmpty {
            return stderrText
        }
        if let stdoutText = stdout.trimmedNonEmpty {
            return stdoutText
        }
        return "No diagnostic output was produced."
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }
}
