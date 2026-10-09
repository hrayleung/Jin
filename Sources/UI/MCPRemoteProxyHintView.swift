import SwiftUI

struct MCPRemoteProxyHintView: View {
    let command: String
    let argsText: String
    let onConvert: (MCPHTTPTransportConfig) -> Void

    var body: some View {
        if let proxy = MCPRemoteProxyCommand.parse(commandLine: command, argsText: argsText) {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                Text("Jin can connect to this server directly over HTTP.")
                    .font(.callout)

                Text(proxy.endpoint.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Switch to Remote HTTP") {
                    onConvert(proxy.httpTransport)
                }
                .controlSize(.small)
                .fixedSize()
            }
        }
    }
}
