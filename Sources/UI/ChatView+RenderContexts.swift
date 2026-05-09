import SwiftUI

extension ChatView {
    var singleThreadRenderContext: ChatThreadRenderContext {
        // Always anchor single-layout content on the active thread so the
        // composer's `controls` and the visible message list refer to the
        // same model. Layer 1 attempted to anchor on `panelThreads.first`
        // for continuity when toggling tabs, but that left the user looking
        // at thread A's content while their next message was already routed
        // to thread B — confusing and out of sync with the params shown in
        // the composer.
        renderCache.singleThreadContext(activeThreadID: activeModelThread?.id)
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
