import SwiftUI

extension ChatView {
    var singleThreadRenderContext: ChatThreadRenderContext {
        renderCache.singleThreadContext(activeThreadID: activeModelThread?.id)
    }

    var selectedThreadRenderContexts: [UUID: ChatThreadRenderContext] {
        Dictionary(uniqueKeysWithValues: selectedModelThreads.map { thread in
            (thread.id, threadRenderContext(threadID: thread.id))
        })
    }

    var activeArtifactCatalog: ArtifactCatalog {
        if let activeThreadID, activeModelThread != nil {
            return threadRenderContext(threadID: activeThreadID).artifactCatalog
        }
        return renderCache.artifactCatalog
    }

    var selectedArtifactIDBinding: Binding<String?> {
        Binding(
            get: {
                guard let threadID = activeModelThread?.id else { return nil }
                return selectedArtifactIDByThreadID[threadID]
            },
            set: { newValue in
                guard let threadID = activeModelThread?.id else { return }
                selectedArtifactIDByThreadID[threadID] = newValue
            }
        )
    }

    var selectedArtifactVersionBinding: Binding<Int?> {
        Binding(
            get: {
                guard let threadID = activeModelThread?.id else { return nil }
                return selectedArtifactVersionByThreadID[threadID]
            },
            set: { newValue in
                guard let threadID = activeModelThread?.id else { return }
                selectedArtifactVersionByThreadID[threadID] = newValue
            }
        )
    }

    func threadRenderContext(threadID: UUID) -> ChatThreadRenderContext {
        renderCache.threadContext(
            threadID: threadID,
            allMessages: conversationEntity.messages,
            sortedThreads: sortedModelThreads,
            currentModelName: currentModelName,
            modelNameForThread: { thread in
                modelName(id: thread.modelID, providerID: thread.providerID)
            },
            assistantProviderIconID: { providerID in
                providerIconID(for: providerID)
            }
        )
    }
}
