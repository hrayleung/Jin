import Foundation

/// A server-side code execution activity from a provider's built-in code execution tool.
///
/// Normalized across providers:
/// - OpenAI: `code_interpreter` tool in Responses API
/// - Anthropic: `code_execution_20250522` tool in Messages API
struct CodeExecutionActivity: Codable, Identifiable, Sendable {
    let id: String
    let status: CodeExecutionStatus
    /// The code being executed (streamed incrementally for OpenAI).
    let code: String?
    /// Standard output from the execution.
    let stdout: String?
    /// Standard error from the execution.
    let stderr: String?
    /// Exit code from the execution (Anthropic).
    let returnCode: Int?
    /// Output images from the execution (OpenAI code interpreter).
    let outputImages: [CodeExecutionOutputImage]?
    /// Output files produced by the execution.
    let outputFiles: [CodeExecutionOutputFile]?
    /// Container ID used for the execution (OpenAI).
    let containerID: String?

    init(
        id: String,
        status: CodeExecutionStatus,
        code: String? = nil,
        stdout: String? = nil,
        stderr: String? = nil,
        returnCode: Int? = nil,
        outputImages: [CodeExecutionOutputImage]? = nil,
        outputFiles: [CodeExecutionOutputFile]? = nil,
        containerID: String? = nil
    ) {
        self.id = id
        self.status = status
        self.code = code
        self.stdout = stdout
        self.stderr = stderr
        self.returnCode = returnCode
        self.outputImages = outputImages
        self.outputFiles = outputFiles
        self.containerID = containerID
    }

    func merged(with newer: CodeExecutionActivity) -> CodeExecutionActivity {
        CodeExecutionActivity(
            id: id,
            status: newer.status,
            code: newer.code ?? code,
            stdout: newer.stdout ?? stdout,
            stderr: newer.stderr ?? stderr,
            returnCode: newer.returnCode ?? returnCode,
            outputImages: newer.outputImages ?? outputImages,
            outputFiles: newer.outputFiles ?? outputFiles,
            containerID: newer.containerID ?? containerID
        )
    }
}

/// Status of a code execution activity.
enum CodeExecutionStatus: Codable, Sendable, Equatable {
    case inProgress
    case writingCode
    case interpreting
    case completed
    case failed
    case incomplete
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "in_progress":
            self = .inProgress
        case "writing_code":
            self = .writingCode
        case "interpreting":
            self = .interpreting
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        case "incomplete":
            self = .incomplete
        default:
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .inProgress:
            return "in_progress"
        case .writingCode:
            return "writing_code"
        case .interpreting:
            return "interpreting"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .incomplete:
            return "incomplete"
        case .unknown(let value):
            return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = CodeExecutionStatus(rawValue: value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// An output image from code execution (OpenAI code interpreter).
struct CodeExecutionOutputImage: Codable, Sendable {
    let url: String

    init(url: String) {
        self.url = url
    }
}

/// A file generated or exposed by a provider-native code execution tool.
struct CodeExecutionOutputFile: Codable, Sendable, Hashable {
    let id: String

    init(id: String) {
        self.id = id
    }
}
