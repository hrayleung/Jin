import SwiftUI
import SwiftData

extension ChatView {
    var detailHeaderBar: some View {
        ChatHeaderBarView(
            isSidebarHidden: isSidebarHidden,
            onToggleSidebar: onToggleSidebar,
            onNewChat: onNewChat,
            titlebarLeadingInset: titlebarLeadingInset,
            mainSidebarWidth: mainSidebarWidth,
            currentProviderIconID: currentProviderIconID,
            currentModelName: currentModelName,
            modelPickerHelpText: providerType == .claudeManagedAgents ? "Select managed agent or model" : "Select model",
            toolbarThreads: headerToolbarThreads,
            isModelPickerPresented: $isModelPickerPresented,
            isAddModelPickerPresented: $isAddModelPickerPresented,
            isStarred: conversationEntity.isStarred == true,
            starShortcutLabel: shortcutsStore.binding(for: .toggleStarChat)?.displayLabel,
            addModelShortcutLabel: shortcutsStore.binding(for: .addModelToChat)?.displayLabel,
            onToggleStar: {
                conversationEntity.isStarred = !(conversationEntity.isStarred == true)
                try? modelContext.save()
            },
            onOpenAssistantInspector: { isAssistantInspectorPresented = true },
            onRequestDeleteConversation: onRequestDeleteConversation,
            onToggleToolbarThread: { threadID in
                guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
                toggleThreadSelection(thread)
            },
            onActivateToolbarThread: activateThread(by:),
            onRemoveToolbarThread: { threadID in
                guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
                removeModelThread(thread)
            }
        ) {
            modelPickerPopoverContent(includeManagedAgentSelection: true) { providerID, modelID in
                setProviderAndModel(providerID: providerID, modelID: modelID)
                isModelPickerPresented = false
            }
        } addModelPopover: {
            modelPickerPopoverContent(includeManagedAgentSelection: false) { providerID, modelID in
                addOrActivateThread(providerID: providerID, modelID: modelID)
                isAddModelPickerPresented = false
            }
        }
    }

    var headerToolbarThreads: [ChatHeaderToolbarThread] {
        ChatThreadSupport.headerToolbarThreads(
            secondaryThreads: secondaryToolbarThreads,
            sortedThreadCount: sortedModelThreads.count,
            providerIconID: { providerID in
                providerIconID(for: providerID)
            },
            modelName: { modelID, providerID in
                modelName(id: modelID, providerID: providerID)
            },
            isActiveThread: { thread in
                isActiveThread(thread)
            }
        )
    }

    func modelPickerPopoverContent(
        includeManagedAgentSelection: Bool,
        onSelect: @escaping (String, String) -> Void
    ) -> some View {
        ModelPickerPopover(
            favoritesStore: favoriteModelsStore,
            providers: providers,
            selectedProviderID: activeProviderID,
            selectedModelID: activeModelID,
            managedAgentContext: includeManagedAgentSelection ? currentManagedAgentPickerContext : nil,
            onSelect: onSelect
        )
    }

    var currentManagedAgentPickerContext: ModelPickerPopover.ManagedAgentContext? {
        guard providerType == .claudeManagedAgents,
              let currentProvider else { return nil }

        let resolvedControls = resolvedClaudeManagedControls(
            for: activeProviderID,
            threadControls: controls
        )

        return ModelPickerPopover.ManagedAgentContext(
            provider: currentProvider,
            selectedAgentID: resolvedControls.claudeManagedAgentID,
            availableAgents: resolvedClaudeManagedAgentOptions(
                for: activeProviderID,
                threadControls: controls
            ),
            isRefreshing: isRefreshingClaudeManagedSessionResources,
            onRefresh: {
                Task { await refreshClaudeManagedAgentSessionResources() }
            },
            onOpenSettings: {
                openClaudeManagedAgentSessionSettingsEditor()
            },
            onSelectAgent: { descriptor in
                applyClaudeManagedAgentSelection(descriptor)
                isModelPickerPresented = false
            }
        )
    }
}
