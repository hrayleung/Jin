import Foundation

extension OpenAIAdapter {
    func parseCodeInterpreterOutputItem(
        _ item: ResponsesAPIOutputItemAddedEvent.Item,
        state: inout OpenAICodeInterpreterState
    ) -> CodeExecutionActivity? {
        guard let id = item.id else { return nil }

        var stdout: String?
        var outputImages: [CodeExecutionOutputImage]?

        if let outputs = item.outputs {
            var logLines: [String] = []
            var images: [CodeExecutionOutputImage] = []

            for output in outputs {
                if output.type == "logs", let logs = output.logs {
                    logLines.append(logs)
                } else if output.type == "image" {
                    if let url = output.url ?? output.imageUrl {
                        images.append(CodeExecutionOutputImage(url: url))
                    }
                }
            }

            if !logLines.isEmpty {
                stdout = logLines.joined(separator: "\n")
            }
            if !images.isEmpty {
                outputImages = images
            }
        }

        let status: CodeExecutionStatus
        switch item.status {
        case "completed":
            status = .completed
        case "failed":
            status = .failed
        case "incomplete":
            status = .incomplete
        case "interpreting":
            status = .interpreting
        default:
            status = .completed
        }

        state.currentItemID = nil

        return CodeExecutionActivity(
            id: id,
            status: status,
            code: item.code ?? state.codeBuffer,
            stdout: stdout,
            outputImages: outputImages,
            containerID: item.containerId
        )
    }
}
