import SwiftUI

/// Labeled engine chip for Web Search chrome. Always includes the engine name
/// so a circular mark cannot be read as another site favicon.
struct SearchActivityEngineIconView: View {
    let provider: SearchPluginProvider?
    var fallbackSystemImage: String = "magnifyingglass"
    var size: CGFloat = 14

    var body: some View {
        if let provider {
            HStack(spacing: 5) {
                MCPIconView(
                    iconID: provider.mcpIconID,
                    fallbackSystemName: fallbackSystemImage,
                    size: size
                )
                Text(provider.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(JinSemanticColor.textSecondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Searched with \(provider.displayName)"))
            .help(provider.displayName)
        }
    }
}
