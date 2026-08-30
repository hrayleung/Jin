import SwiftUI

struct MCPHTTPAuthViews: View {
    let serverID: String
    @Binding var endpoint: String
    @Binding var httpAuthKind: MCPHTTPAuthentication.FormKind
    @Binding var bearerToken: String
    @Binding var authHeaderName: String
    @Binding var authHeaderValue: String
    @Binding var isBearerTokenVisible: Bool
    @Binding var isHeaderValueVisible: Bool
    let authenticationError: String?
    var showsMethodPicker = true
    var compact = false

    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var isSignedIn = false
    @State private var signedInExpiry: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            if !compact {
                Text("Authentication")
                    .font(.headline)
            }

            if showsMethodPicker {
                LabeledContent("Method") {
                    Picker("Method", selection: $httpAuthKind) {
                        ForEach(availableAuthKinds, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            switch httpAuthKind {
            case .oauth:
                oauthBody
            case .bearerToken:
                VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                    tokenField(
                        title: isParallelSearchMCP ? "API key" : "Bearer token",
                        text: $bearerToken,
                        isRevealed: $isBearerTokenVisible
                    )
                    if isParallelSearchMCP {
                        Text("Sent as Authorization: Bearer. Get a key at platform.parallel.ai.")
                            .font(.caption)
                            .foregroundStyle(JinSemanticColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if MCPHTTPAuthentication.FormKind.isGitHubRemoteMCP(endpoint) {
                        Text("GitHub’s remote MCP uses a personal access token. Create one at github.com/settings/tokens.")
                            .font(.caption)
                            .foregroundStyle(JinSemanticColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            case .customHeader:
                VStack(alignment: .leading, spacing: JinSpacing.small) {
                    labeled("Header name") {
                        JinSettingsTextField("X-API-Key", text: $authHeaderName, usesMonospacedFont: true)
                    }
                    tokenField(
                        title: "Header value",
                        text: $authHeaderValue,
                        isRevealed: $isHeaderValueVisible
                    )
                }
            case .none:
                Text(
                    isParallelSearchMCP
                        ? "Parallel Search works without an account at lower rate limits. Sign in or add an API key for higher limits."
                        : "This server doesn’t need credentials."
                )
                    .font(.caption)
                    .foregroundStyle(JinSemanticColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let authenticationError {
                Text(authenticationError)
                    .jinInlineErrorText()
            }
        }
        .onAppear {
            coerceAuthKindIfNeeded()
            alignParallelEndpointIfNeeded()
            refreshStatus()
        }
        .onChange(of: serverID) { _, _ in refreshStatus() }
        .onChange(of: endpoint) { _, _ in
            coerceAuthKindIfNeeded()
            refreshStatus()
        }
        .onChange(of: httpAuthKind) { _, _ in
            alignParallelEndpointIfNeeded()
            refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mcpOAuthStatusDidChange)) { _ in
            refreshStatus()
        }
    }

    private var oauthBody: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            HStack(spacing: JinSpacing.small) {
                Circle()
                    .fill(isSignedIn ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.subheadline.weight(.medium))
                Spacer()
            }

            Text(oauthHelpText)
                .font(.caption)
                .foregroundStyle(JinSemanticColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: JinSpacing.small) {
                Button {
                    Task { await signIn() }
                } label: {
                    HStack(spacing: 6) {
                        if isSigningIn {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSignedIn ? "Sign in again" : "Sign in")
                    }
                }
                .disabled(isSigningIn || MCPServerFormSupport.parsedEndpoint(endpoint) == nil)

                if isSignedIn {
                    Button("Sign out", role: .destructive) {
                        if let url = MCPServerFormSupport.parsedEndpoint(endpoint) {
                            MCPOAuthCoordinator.signOut(endpoint: url, legacyServerID: serverID)
                        }
                        refreshStatus()
                    }
                    .disabled(isSigningIn)
                }
            }

            if let signInError {
                Text(signInError)
                    .jinInlineErrorText()
            }
        }
    }

    private func tokenField(
        title: String,
        text: Binding<String>,
        isRevealed: Binding<Bool>
    ) -> some View {
        labeled(title) {
            JinRevealableSecureField(
                prompt: "",
                text: text,
                isRevealed: isRevealed,
                usesMonospacedFont: true,
                revealHelp: "Show \(title.lowercased())",
                concealHelp: "Hide \(title.lowercased())"
            )
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)
                .font(.subheadline.weight(.medium))
            content()
        }
    }

    private var availableAuthKinds: [MCPHTTPAuthentication.FormKind] {
        MCPHTTPAuthentication.FormKind.available(forEndpoint: endpoint)
    }

    private var oauthHelpText: String {
        if isParallelSearchMCP {
            return "Opens your browser and signs in with Parallel. Tokens stay on this Mac. For anonymous light use, switch Method to None."
        }
        return "Opens your browser and uses the official MCP OAuth 2.1 flow (PKCE). Tokens stay on this Mac."
    }

    private var isParallelSearchMCP: Bool {
        MCPParallelSearchEndpoint.isSearchMCP(endpoint)
    }

    private func coerceAuthKindIfNeeded() {
        let coerced = MCPHTTPAuthentication.FormKind.coerced(httpAuthKind, forEndpoint: endpoint)
        if coerced != httpAuthKind {
            httpAuthKind = coerced
        }
    }

    private var statusText: String {
        if isSignedIn {
            if let signedInExpiry {
                return "Signed in · expires \(signedInExpiry.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Signed in"
        }
        return "Not signed in"
    }

    private func refreshStatus() {
        guard let url = MCPServerFormSupport.parsedEndpoint(endpoint) else {
            isSignedIn = false
            signedInExpiry = nil
            return
        }
        let session = MCPOAuthCoordinator.status(for: url, legacyServerID: serverID)
        isSignedIn = session?.value.trimmedNonEmpty != nil
        signedInExpiry = session?.expiresAt
    }

    private func alignParallelEndpointIfNeeded() {
        let aligned = MCPParallelSearchEndpoint.aligned(endpoint, to: httpAuthKind)
        if aligned != endpoint {
            endpoint = aligned
        }
    }

    private func signIn() async {
        signInError = nil
        alignParallelEndpointIfNeeded()
        guard let url = MCPServerFormSupport.parsedEndpoint(endpoint) else {
            signInError = MCPOAuthError.missingEndpoint.localizedDescription
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            try await MCPOAuthCoordinator.signIn(endpoint: url, legacyServerID: serverID)
            refreshStatus()
        } catch {
            signInError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            refreshStatus()
        }
    }
}
