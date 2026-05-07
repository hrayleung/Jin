import Foundation

extension CodeExecutionSheetSupport {
    static func providerSettingsInfo(for providerType: ProviderType?) -> (title: String, body: String) {
        switch providerType {
        case .claudeManagedAgents:
            return (
                "Claude Managed Agents",
                "Code execution runs inside the selected managed agent session environment. Jin does not expose per-request container controls here."
            )
        case .gemini:
            return (
                "Gemini API (AI Studio)",
                "Gemini code execution has no request-level tuning fields in Jin. Supported Files API uploads can be combined with code execution after they become ACTIVE. Spreadsheet files like .xlsx are not sent as mounted files; Jin falls back to extracted text when possible."
            )
        case .vertexai:
            return (
                "Vertex AI",
                "Vertex AI code execution has no request-level tuning fields in Jin. Vertex AI documents remain prompt context only: the code execution sandbox does not support file I/O."
            )
        case .xai:
            return (
                "xAI",
                "xAI code execution currently has no additional request parameters exposed in Jin."
            )
        default:
            return (
                providerType?.displayName ?? "Provider",
                "No provider-specific code execution parameters are exposed for this provider."
            )
        }
    }

    static func summaryText(for providerType: ProviderType?) -> String {
        switch providerType {
        case .openai, .openaiWebSocket:
            return "OpenAI supports request-level container configuration for code interpreter, including memory limits, extra file IDs, and explicit container reuse."
        case .anthropic:
            return "Anthropic supports reusable code execution containers. Supported uploaded files can be attached directly to the sandbox."
        case .claudeManagedAgents:
            return "Claude Managed Agents runs tools inside the selected remote agent environment and session."
        case .gemini:
            return "Gemini supports code execution, but there are no extra request fields to tune here."
        case .vertexai:
            return "Vertex AI supports code execution, but the sandbox does not support file I/O."
        default:
            return "Provider-native code execution lets the model write and run code inside a managed sandbox."
        }
    }

    static func providerDetailText(for providerType: ProviderType?) -> String {
        switch providerType {
        case .openai, .openaiWebSocket:
            return "Auto creates a request-scoped container. Existing sends a pre-created container reference."
        case .anthropic:
            return "Claude can reuse a container between requests. Supported uploads are mounted into the sandbox."
        case .claudeManagedAgents:
            return "Managed agents provision execution inside the remote session environment selected in thread settings."
        default:
            return "Configuration changes apply only to this conversation."
        }
    }

    static func badgeText(
        isEnabled: Bool,
        providerType: ProviderType?,
        controls: CodeExecutionControls?
    ) -> String? {
        guard isEnabled else { return nil }

        switch providerType {
        case .openai, .openaiWebSocket:
            if controls?.openAI?.normalizedExistingContainerID != nil {
                return "reuse"
            }
            return controls?.openAI?.container?.normalizedMemoryLimit
        case .anthropic:
            return controls?.anthropic?.normalizedContainerID == nil ? nil : "reuse"
        default:
            return nil
        }
    }

    static func helpText(
        isEnabled: Bool,
        providerType: ProviderType?,
        controls: CodeExecutionControls?
    ) -> String {
        guard isEnabled else { return "Code Execution: Off" }

        switch providerType {
        case .openai, .openaiWebSocket:
            if let containerID = controls?.openAI?.normalizedExistingContainerID {
                return "Code Execution: Reuse \(containerID)"
            }
            if let memoryLimit = controls?.openAI?.container?.normalizedMemoryLimit {
                return "Code Execution: Auto container (\(memoryLimit))"
            }
            return "Code Execution: Auto container"
        case .anthropic:
            if controls?.anthropic?.normalizedContainerID != nil {
                return "Code Execution: Reuse container"
            }
            return "Code Execution: On"
        case .vertexai:
            return "Code Execution: On (no file I/O in sandbox)"
        default:
            return "Code Execution: On"
        }
    }
}
