import SwiftUI

extension ChatView {
    var singleThreadRenderContext: ChatThreadRenderContext {
        // Anchor single-layout content on the first panel thread (the one
        // with the most recent messages we want to show), falling back to
        // the active thread when no panel exists yet (brand-new chat).
        let anchorThreadID = panelThreads.first?.id ?? activeModelThread?.id
        return renderCache.singleThreadContext(activeThreadID: anchorThreadID)
    }

    var panelThreadRenderContexts: [UUID: ChatThreadRenderContext] {
        Dictionary(uniqueKeysWithValues: panelThreads.map { thread in
            (thread.id, threadRenderContext(threadID: thread.id))
        })
    }

    var selectedThreadRenderContexts: [UUID: ChatThreadRenderContext] {
        Dictionary(uniqueKeysWithValues: selectedModelThreads.map { thread in
            (thread.id, threadRenderContext(threadID: thread.id))
        })
    }

    var activeArtifactCatalog: ArtifactCatalog {
        if let activeThreadID = activeModelThread?.id {
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
