import SwiftUI
import SwiftData

@main
struct JinApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: ConversationEntity.self,
                AssistantEntity.self,
                MessageEntity.self,
                ProviderConfigEntity.self,
                MCPServerConfigEntity.self,
                AttachmentEntity.self
            )
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)

        Settings {
            SettingsView()
        }
        .modelContainer(modelContainer)
    }
}
