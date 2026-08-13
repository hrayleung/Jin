import SwiftUI

struct MCPHTTPAuthViews: View {
    let serverID: String
    let endpoint: String
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
                Picker("Method", selection: $httpAuthKind) {
                    ForEach(MCPHTTPAuthentication.FormKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            switch httpAuthKind {
            case .oauth:
                oauthBody
            case .bearerToken:
                tokenField(
                    title: "Bearer token",
                    text: $bearerToken,
                    isRevealed: $isBearerTokenVisible
                )
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
                Text("This server doesn’t need credentials.")
                    .font(.caption)
                    .foregroundStyle(JinSemanticColor.textSecondary)
            }

            if let authenticationError {
                Text(authenticationError)
                    .jinInlineErrorText()
            }
        }
        .onAppear(perform: refreshStatus)
        .onChange(of: serverID) { _, _ in refreshStatus() }
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

            Text("Opens your browser and uses the official MCP OAuth 2.1 flow (PKCE). Tokens stay on this Mac.")
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
                        MCPOAuthCoordinator.signOut(serverID: serverID)
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
                title: title,
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
        let session = MCPOAuthCoordinator.status(for: serverID)
        isSignedIn = session?.value.trimmedNonEmpty != nil
        signedInExpiry = session?.expiresAt
    }

    private func signIn() async {
        signInError = nil
        guard let url = MCPServerFormSupport.parsedEndpoint(endpoint) else {
            signInError = MCPOAuthError.missingEndpoint.localizedDescription
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            try await MCPOAuthCoordinator.signIn(serverID: serverID, endpoint: url)
            refreshStatus()
        } catch {
            signInError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            refreshStatus()
        }
    }
}
