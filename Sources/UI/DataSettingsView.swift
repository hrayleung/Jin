import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct DataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var conversations: [ConversationEntity]

    @State private var showingDeleteAllChatsConfirmation = false

    var body: some View {
        Form {
            Section("Data") {
                Text("These actions affect local data stored on this Mac.")
                    .jinInfoCallout()

                LabeledContent("Chats") {
                    Text("\(conversations.count)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button {
                    openDataDirectory()
                } label: {
                    Label("Open Data Directory", systemImage: "folder")
                }

                Button("Delete All Chats", role: .destructive) {
                    showingDeleteAllChatsConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .confirmationDialog("Delete all chats?", isPresented: $showingDeleteAllChatsConfirmation) {
            Button("Delete All Chats", role: .destructive) {
                deleteAllChats()
            }
        } message: {
            Text("This will permanently delete all chats across all assistants.")
        }
    }

    private func deleteAllChats() {
        for conversation in conversations {
            modelContext.delete(conversation)
        }
    }

    private func openDataDirectory() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }

        let jinDir = appSupport.appendingPathComponent("Jin", isDirectory: true)

        if FileManager.default.fileExists(atPath: jinDir.path) {
            NSWorkspace.shared.open(jinDir)
        } else {
            NSWorkspace.shared.open(appSupport)
        }
    }
}
