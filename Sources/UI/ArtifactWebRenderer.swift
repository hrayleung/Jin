import SwiftUI
import WebKit
import AppKit

private let artifactTemplateURL = JinResourceBundle.url(forResource: "artifact-template", withExtension: "html")

struct ArtifactWebRenderer: View {
    let artifact: RenderedArtifactVersion

    var body: some View {
        if artifactTemplateURL != nil {
            ArtifactWebRendererRepresentable(artifact: artifact)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Artifact Renderer Missing",
                systemImage: "exclamationmark.triangle",
                description: Text("artifact-template.html is missing from the app bundle.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ArtifactWebRendererRepresentable: NSViewRepresentable {
    let artifact: RenderedArtifactVersion

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.pendingArtifact = artifact

        if let artifactTemplateURL {
            webView.loadFileURL(artifactTemplateURL, allowingReadAccessTo: artifactTemplateURL.deletingLastPathComponent())
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.pendingArtifact = artifact
        context.coordinator.renderIfNeeded(artifact, in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var pendingArtifact: RenderedArtifactVersion?
        private var isReady = false
        private var lastRenderedArtifactID: String?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            if let pendingArtifact {
                renderIfNeeded(pendingArtifact, in: webView, force: true)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                if let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                    NSWorkspace.shared.open(url)
                }
                return .cancel
            }
            return .allow
        }

        func renderIfNeeded(_ artifact: RenderedArtifactVersion, in webView: WKWebView, force: Bool = false) {
            guard isReady else { return }

            let renderID = artifact.id
            guard force || renderID != lastRenderedArtifactID else { return }
            lastRenderedArtifactID = renderID

            let payload: [String: Any] = [
                "artifactID": artifact.artifactID,
                "title": artifact.title,
                "contentType": artifact.contentType.rawValue,
                "content": artifact.content,
                "version": artifact.version
            ]

            if #available(macOS 11.0, *) {
                webView.callAsyncJavaScript(
                    "window.renderArtifact(payload)",
                    arguments: ["payload": payload],
                    in: nil,
                    in: .page,
                    completionHandler: { _ in }
                )
            } else if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
                      let json = String(data: data, encoding: .utf8) {
                webView.evaluateJavaScript("window.renderArtifact(\(json))", completionHandler: nil)
            }
        }
    }
}
