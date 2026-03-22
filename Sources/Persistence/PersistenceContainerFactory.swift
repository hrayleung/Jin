import Foundation
import SwiftData

enum PersistenceContainerFactory {
    static func makeContainer(storeURL: URL? = nil) throws -> ModelContainer {
        let resolvedStoreURL = try storeURL ?? AppDataLocations.storeURL()
        let configuration = ModelConfiguration(url: resolvedStoreURL)
        return try ModelContainer(
            for: ConversationEntity.self,
            ConversationModelThreadEntity.self,
            AssistantEntity.self,
            MessageEntity.self,
            ProviderConfigEntity.self,
            MCPServerConfigEntity.self,
            AttachmentEntity.self,
            configurations: configuration
        )
    }

    static func fetchCoreCounts(in container: ModelContainer) -> SnapshotCoreCounts {
        let context = ModelContext(container)
        return SnapshotCoreCounts(
            conversations: (try? context.fetchCount(FetchDescriptor<ConversationEntity>())) ?? 0,
            messages: (try? context.fetchCount(FetchDescriptor<MessageEntity>())) ?? 0,
            providers: (try? context.fetchCount(FetchDescriptor<ProviderConfigEntity>())) ?? 0,
            assistants: (try? context.fetchCount(FetchDescriptor<AssistantEntity>())) ?? 0,
            mcpServers: (try? context.fetchCount(FetchDescriptor<MCPServerConfigEntity>())) ?? 0
        )
    }
}
