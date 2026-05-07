import SwiftUI

struct OnDeviceModelStorageDisclosure: View {
    let repositoryRootURL: URL
    let guidanceText: String
    let onOpenFolder: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        DisclosureGroup("Storage & Manual Import") {
            repositoryPath
            actionRow
            importGuidance
        }
    }

    private var repositoryPath: some View {
        Text(repositoryRootURL.path)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                onOpenFolder()
            } label: {
                Label("Open Folder", systemImage: "folder")
            }

            Button("Refresh") {
                onRefresh()
            }

            CopyToPasteboardButton(
                text: repositoryRootURL.path,
                helpText: "Copy folder path",
                useProminentStyle: false
            )

            Spacer()
        }
        .controlSize(.small)
    }

    private var importGuidance: some View {
        Text(guidanceText)
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}
