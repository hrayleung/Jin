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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.large) {
                    JinSettingsCard(spacing: JinSpacing.large) {
                        fieldBlock(
                            title: "Endpoint URL",
                            prompt: "https://workspace--app-server.us-west.modal.direct",
                            helperText: helperText,
                            helperIsError: resolvedHost == nil && hasTypedEndpoint,
                            text: $rawEndpoint,
                            monospaced: true
                        )

                        fieldBlock(
                            title: "Name",
                            prompt: "Optional",
                            helperText: nil,
                            helperIsError: false,
                            text: $nickname,
                            monospaced: false
                        )
                    }

                    if let lookupError {
                        Text(lookupError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(JinSpacing.xLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(JinSemanticColor.detailSurface)
            .navigationTitle("Add Endpoint")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isLookingUp)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLookingUp {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Add") { addEndpoint() }
                            .disabled(!canAdd)
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 320)
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

    private func fieldBlock(
        title: String,
        prompt: String,
        helperText: String?,
        helperIsError: Bool,
        text: Binding<String>,
        monospaced: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)
                .font(.subheadline.weight(.medium))

            TextField("", text: text, prompt: Text(prompt))
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textFieldStyle(.plain)
                .padding(.horizontal, JinSpacing.medium)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .fill(JinSemanticColor.textSurface)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .stroke(JinSemanticColor.separator.opacity(0.55), lineWidth: JinStrokeWidth.hairline)
                }
                .onSubmit {
                    if canAdd { addEndpoint() }
                }

            if let helperText, !helperText.isEmpty {
                Text(helperText)
                    .font(.caption)
                    .foregroundStyle(helperIsError ? Color.orange : Color.secondary)
            }
        }
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
