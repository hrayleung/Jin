import Foundation

// MARK: - Server Request Handling

extension CodexAppServerAdapter {
    func handleServerRequest(
        id: JSONRPCID,
        method: String,
        params: [String: JSONValue]?,
        with client: CodexWebSocketRPCClient,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation?
    ) async throws {
        let params = params ?? [:]

        if let continuation,
           let interaction = Self.interactionRequest(id: id, method: method, params: params) {
            continuation.yield(.codexInteractionRequest(interaction))
            let response = await withTaskCancellationHandler(
                operation: {
                    await interaction.waitForResponse()
                },
                onCancel: {
                    Task {
                        await interaction.resolve(.cancelled(message: nil))
                    }
                }
            )
            try await Self.sendInteractionResponse(
                response,
                for: interaction,
                requestID: id,
                client: client
            )
            return
        }

        if let autoReply = CodexAppServerAutoReply.result(forServerRequestMethod: method) {
            try await client.respond(id: id, result: autoReply)
            return
        }

        let message: String
        switch method {
        case "item/tool/call", "item/tool/requestUserInput":
            message = "Client callbacks are disabled for this Codex App Server provider."
        default:
            message = "Unsupported server request method: \(method)"
        }

        try await client.respondWithError(
            id: id,
            code: -32601,
            message: message
        )
    }
}
