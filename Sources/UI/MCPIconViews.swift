import SwiftUI

struct MCPIconView: View {
    @Environment(\.colorScheme) private var colorScheme

    let iconID: String?
    var fallbackSystemName: String = "server.rack"
    var size: CGFloat = 18

    var body: some View {
        if let iconImage {
            iconImage
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            fallbackIcon
        }
    }

    private var iconImage: Image? {
        guard let icon = MCPIconCatalog.icon(forID: iconID),
              let nsImage = icon.localPNGImage(useDarkMode: colorScheme == .dark) else {
            return nil
        }
        return Image(nsImage: nsImage)
    }

    private var fallbackIcon: some View {
        Image(systemName: fallbackSystemName)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.8, height: size * 0.8)
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}
