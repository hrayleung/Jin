import SwiftUI

/// Adds one Modal endpoint as a selectable model.
///
/// Official docs: `POST <endpoint-url>/v1/chat/completions` with the Hugging
/// Face repo ID as `model`. Region lives on the URL Modal already gave you.
struct AddModalEndpointSheet: View {
    @Environment(\.dismiss) private var dismiss

    var apiKey: String = ""
    let onAdd: (ModelInfo) -> Void

    @State private var rawEndpoint = ""
    @State private var nickname = ""
    @State private var isLookingUp = false
    @State private var lookupError: String?

    var body: some View {
        JinSheet("Add Endpoint") {
            JinSettingsPage(horizontalPadding: 0, verticalPadding: 0) {
                JinSettingsSection("Endpoint") {
                    JinSettingsTextFieldRow(
                        "URL", prompt: "https://…modal.direct", text: $rawEndpoint, usesMonospacedFont: true)
                    JinSettingsTextFieldRow("Display name", prompt: "Optional", text: $nickname)
                    if let helperText {
                        Text(helperText)
                            .font(.caption)
                            .foregroundStyle(resolvedHost == nil && hasTypedEndpoint ? Color.orange : Color.secondary)
                    }
                    if let lookupError {
                        JinSettingsErrorText(text: lookupError)
                    }
                }
            }
        } actions: {
            Button("Cancel") { dismiss() }
                .disabled(isLookingUp)
                .keyboardShortcut(.cancelAction)
            if isLookingUp {
                ProgressView().controlSize(.small)
            }
            Button(isLookingUp ? "Adding…" : "Add") { addEndpoint() }
                .disabled(!canAdd)
                .keyboardShortcut(.defaultAction)
        }
        .frame(width: 560, height: 340)
    }

    private var hasTypedEndpoint: Bool {
        !rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedHost: String? {
        ModalEndpointSupport.autoEndpointHost(from: rawEndpoint)
    }

    private var canAdd: Bool {
        resolvedHost != nil && !isLookingUp
    }

    private var helperText: String? {
        guard hasTypedEndpoint, resolvedHost == nil else { return nil }
        let trimmed = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let host = url.host, ModalEndpointSupport.isSharedAPIHost(host) {
            return "That’s Modal’s shared catalog host, not a model endpoint."
        }
        return "Use the endpoint URL from the Modal dashboard."
    }

    private func addEndpoint() {
        guard let host = resolvedHost else { return }
        isLookingUp = true
        lookupError = nil

        Task {
            let upstreamID = await lookupUpstreamModelID(host: host)
            await MainActor.run {
                isLookingUp = false
                guard let model = ModalEndpointSupport.modelInfo(
                    fromPasted: rawEndpoint,
                    nickname: nickname,
                    upstreamModelID: upstreamID
                ) else { return }
                onAdd(model)
                dismiss()
            }
        }
    }

    private func lookupUpstreamModelID(host: String) async -> String? {
        let token = apiKey.trimmed
        guard !token.isEmpty else { return nil }

        let urlString = "\(ModalEndpointSupport.chatBaseURL(forHost: host))/models"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let headers = ModalAdapter.authHeaders(for: token)
        if let auth = headers.auth {
            request.setValue(auth.value, forHTTPHeaderField: auth.key)
            for (key, value) in headers.additional {
                request.setValue(value, forHTTPHeaderField: key)
            }
        } else {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            return decoded.data
                .map(\.id)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } catch {
            return nil
        }
    }
}
