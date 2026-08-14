import SwiftUI

struct MCPRemoteProxyHintView: View {
    let command: String
    let argsText: String
    let onConvert: (MCPHTTPTransportConfig) -> Void

    var body: some View {
        if let proxy = MCPRemoteProxyCommand.parse(commandLine: command, argsText: argsText) {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                Text("This command only proxies \(proxy.endpoint.absoluteString) through Node. Jin can connect to that URL directly over HTTP — no npx or mcp-remote required.")
                    .jinInfoCallout()

                Button("Switch to Remote HTTP") {
                    onConvert(proxy.httpTransport)
                }
            }
        }
    }
}
