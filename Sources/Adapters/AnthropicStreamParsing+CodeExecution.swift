import Foundation

extension AnthropicAdapter {
    func codeExecutionActivityFromToolResult(
        contentBlock: AnthropicStreamEvent.ContentBlock,
        outputIndex: Int
    ) -> CodeExecutionActivity? {
        let id = contentBlock.toolUseId ?? contentBlock.id ?? "anthropic_code_exec_\(outputIndex)"

        guard let resultContent = contentBlock.codeExecutionContent else {
            return CodeExecutionActivity(
                id: id,
                status: .completed
            )
        }

        if resultContent.type == "code_execution_tool_result_error"
            || resultContent.type == "bash_code_execution_tool_result_error"
            || resultContent.type == "text_editor_code_execution_tool_result_error" {
            return CodeExecutionActivity(
                id: id,
                status: .failed,
                stderr: resultContent.errorCode
            )
        }

        let status: CodeExecutionStatus = (resultContent.returnCode ?? 0) == 0 ? .completed : .failed
        let outputFiles = resultContent.content?
            .compactMap { output -> CodeExecutionOutputFile? in
                guard let fileID = output.fileId?.trimmedNonEmpty else {
                    return nil
                }
                return CodeExecutionOutputFile(id: fileID)
            }

        return CodeExecutionActivity(
            id: id,
            status: status,
            stdout: resultContent.stdout,
            stderr: resultContent.stderr,
            returnCode: resultContent.returnCode,
            outputFiles: outputFiles?.isEmpty == true ? nil : outputFiles
        )
    }

    /// Extracts code from accumulated partial JSON.
    /// Handles both legacy `{"code":"..."}` and current `{"command":"..."}` formats.
    /// Since the JSON arrives incrementally, we do a best-effort extraction.
    func extractCodeFromPartialJSON(_ buffer: String) -> String? {
        if let data = buffer.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let code = dict["command"] as? String { return code }
            if let code = dict["code"] as? String { return code }
        }

        let codeKeyRange = buffer.range(of: "\"command\"") ?? buffer.range(of: "\"code\"")
        guard let codeKeyRange else { return nil }
        let afterKey = buffer[codeKeyRange.upperBound...]

        guard let colonIndex = afterKey.firstIndex(of: ":") else { return nil }
        let afterColon = afterKey[afterKey.index(after: colonIndex)...].drop(while: { $0.isWhitespace })

        guard afterColon.first == "\"" else { return nil }
        let stringStart = afterColon.index(after: afterColon.startIndex)
        let remainder = afterColon[stringStart...]

        var result = ""
        var i = remainder.startIndex
        while i < remainder.endIndex {
            let ch = remainder[i]
            if ch == "\\" {
                let next = remainder.index(after: i)
                if next < remainder.endIndex {
                    let escaped = remainder[next]
                    switch escaped {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    default: result.append(ch); result.append(escaped)
                    }
                    i = remainder.index(after: next)
                } else {
                    break
                }
            } else if ch == "\"" {
                break
            } else {
                result.append(ch)
                i = remainder.index(after: i)
            }
        }

        return result.isEmpty ? nil : result
    }
}
