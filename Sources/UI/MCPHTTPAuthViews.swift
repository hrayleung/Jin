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
        Group {
            if compact {
                authenticationFields
            } else {
                VStack(alignment: .leading, spacing: JinSpacing.medium) {
                    Text("Authentication")
                        .font(.headline)
                    authenticationFields
                }
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
        .environment(\.jinSettingsFieldChrome, compact ? .plain : .roundedBorder)
    }

    @ViewBuilder
    private var authenticationFields: some View {
        if showsMethodPicker {
            JinSettingsPickerRow("Method", supportingText: noAuthenticationHelp, selection: $httpAuthKind) {
                ForEach(availableAuthKinds, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
        }

        switch httpAuthKind {
        case .oauth:
            oauthBody
        case .bearerToken:
            tokenField(
                title: isParallelSearchMCP ? "API key" : "Bearer token",
                supportingText: bearerTokenHelp,
                text: $bearerToken,
                isRevealed: $isBearerTokenVisible
            )
        case .customHeader:
            JinSettingsTextFieldRow(
                "Header name", prompt: "X-API-Key", text: $authHeaderName, usesMonospacedFont: true
            )
            tokenField(
                title: "Header value",
                text: $authHeaderValue,
                isRevealed: $isHeaderValueVisible
            )
        case .none:
            if !showsMethodPicker, let noAuthenticationHelp {
                Text(noAuthenticationHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let authenticationError {
            Text(authenticationError)
                .jinInlineErrorText()
        }
    }

    private var oauthBody: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            JinSettingsControlRow("Account", supportingText: accountHelp, controlAlignment: .leading) {
                HStack(spacing: JinSpacing.small) {
                    Text(isSignedIn ? "Signed in" : "Not signed in")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: JinSpacing.small)

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
                    .controlSize(.small)
                    .fixedSize()
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
        supportingText: String? = nil,
        text: Binding<String>,
        isRevealed: Binding<Bool>
    ) -> some View {
        JinSettingsSecureFieldRow(
            title,
            prompt: "Enter credential",
            supportingText: supportingText,
            text: text,
            isRevealed: isRevealed,
            usesMonospacedFont: true,
            revealHelp: "Show \(title.lowercased())",
            concealHelp: "Hide \(title.lowercased())"
        )
    }

    private var availableAuthKinds: [MCPHTTPAuthentication.FormKind] {
        MCPHTTPAuthentication.FormKind.available(forEndpoint: endpoint)
    }

    private var oauthHelpText: String {
        if isParallelSearchMCP {
            return "Sign in with Parallel in your browser. Choose None to use anonymous access."
        }
        return "Sign in through your browser. Credentials stay on this Mac."
    }

    private var noAuthenticationHelp: String? {
        guard httpAuthKind == .none else { return nil }
        return isParallelSearchMCP
            ? "Anonymous access has lower rate limits. Sign in or add an API key for higher limits."
            : "Choose a method if your server requires credentials."
    }

    private var bearerTokenHelp: String? {
        if isParallelSearchMCP {
            return "Get an API key at platform.parallel.ai."
        }
        if MCPHTTPAuthentication.FormKind.isGitHubRemoteMCP(endpoint) {
            return "Use a personal access token from github.com/settings/tokens."
        }
        return nil
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

    private var accountHelp: String {
        if isSignedIn, let signedInExpiry {
            return "Expires \(signedInExpiry.formatted(date: .abbreviated, time: .shortened))."
        }
        return isSignedIn ? "Credentials stay on this Mac." : oauthHelpText
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
