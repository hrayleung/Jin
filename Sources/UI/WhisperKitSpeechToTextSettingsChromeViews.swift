import SwiftUI

struct WhisperKitDownloadedModelRow: View {
    let localModel: WhisperKitService.LocalModel
    let isSelected: Bool
    let isDownloading: Bool
    let onUse: (String) -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    private var title: String {
        WhisperKitModelCatalog.title(for: localModel.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow
            actionRow
        }
        .padding(.vertical, 4)
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))

            Spacer(minLength: 8)

            if isSelected {
                Text("Selected")
                    .jinTagStyle(foreground: Color.accentColor)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if let presetID = localModel.presetID, !isSelected {
                Button("Use This") {
                    onUse(presetID)
                }
            }

            Button("Reveal in Finder") {
                onReveal()
            }

            Button("Remove", role: .destructive) {
                onRemove()
            }
            .disabled(isDownloading)

            Spacer()
        }
        .controlSize(.small)
    }
}
