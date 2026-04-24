import SwiftUI

// MARK: - Slash Command MCP

extension ChatView {

    var slashCommandMCPItems: [SlashCommandMCPServerItem] {
        guard !ManagedAgentUIVisibilitySupport.hidesInternalUI(providerType: providerType) else { return [] }
        return eligibleMCPServers.map { server in
            SlashCommandMCPServerItem(
                id: server.id,
                name: server.name,
                isSelected: perMessageMCPServerIDs.contains(server.id)
            )
        }
    }

    var perMessageMCPChips: [SlashCommandMCPServerItem] {
        guard !ManagedAgentUIVisibilitySupport.hidesInternalUI(providerType: providerType) else { return [] }
        let eligible = Set(eligibleMCPServers.map(\.id))
        return perMessageMCPServerIDs
            .filter { eligible.contains($0) }
            .compactMap { id in
                eligibleMCPServers.first { $0.id == id }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { SlashCommandMCPServerItem(id: $0.id, name: $0.name, isSelected: true) }
    }

    func updateSlashCommandState(for text: String, target: SlashCommandTarget) {
        guard supportsMCPToolsControl, !eligibleMCPServers.isEmpty else {
            if isSlashMCPPopoverVisible {
                isSlashMCPPopoverVisible = false
            }
            return
        }

        if let filter = SlashCommandDetection.detectFilter(in: text) {
            slashMCPFilterText = filter
            slashCommandTarget = target
            if !isSlashMCPPopoverVisible {
                slashMCPHighlightedIndex = 0
                isSlashMCPPopoverVisible = true
            }
            let count = SlashCommandDetection.filteredCount(
                servers: slashCommandMCPItems,
                filterText: filter
            )
            if count > 0, slashMCPHighlightedIndex >= count {
                slashMCPHighlightedIndex = count - 1
            }
        } else if isSlashMCPPopoverVisible, slashCommandTarget == target {
            isSlashMCPPopoverVisible = false
            slashMCPFilterText = ""
            slashMCPHighlightedIndex = 0
        }
    }

    func handleSlashCommandSelectServer(_ serverID: String) {
        if perMessageMCPServerIDs.contains(serverID) {
            perMessageMCPServerIDs.remove(serverID)
        } else {
            perMessageMCPServerIDs.insert(serverID)
        }

        switch slashCommandTarget {
        case .composer:
            messageText = SlashCommandDetection.removeSlashToken(from: messageText)
        case .editMessage:
            editingUserMessageText = SlashCommandDetection.removeSlashToken(from: editingUserMessageText)
        }
        isSlashMCPPopoverVisible = false
        slashMCPFilterText = ""
        slashMCPHighlightedIndex = 0
    }

    func removePerMessageMCPServer(_ serverID: String) {
        perMessageMCPServerIDs.remove(serverID)
    }

    func dismissSlashCommandPopover() {
        switch slashCommandTarget {
        case .composer:
            messageText = SlashCommandDetection.removeSlashToken(from: messageText)
        case .editMessage:
            editingUserMessageText = SlashCommandDetection.removeSlashToken(from: editingUserMessageText)
        }
        isSlashMCPPopoverVisible = false
        slashMCPFilterText = ""
        slashMCPHighlightedIndex = 0
    }

    func handleSlashCommandKeyDown(_ keyCode: UInt16) -> Bool {
        let items = slashCommandMCPItems
        let count = SlashCommandDetection.filteredCount(
            servers: items,
            filterText: slashMCPFilterText
        )
        guard count > 0 else {
            if keyCode == 53 {
                dismissSlashCommandPopover()
                return true
            }
            return false
        }

        switch keyCode {
        case 126:
            slashMCPHighlightedIndex = max(0, slashMCPHighlightedIndex - 1)
            return true
        case 125:
            slashMCPHighlightedIndex = min(count - 1, slashMCPHighlightedIndex + 1)
            return true
        case 36, 76, 48:
            if let serverID = SlashCommandDetection.highlightedServerID(
                servers: items,
                filterText: slashMCPFilterText,
                highlightedIndex: slashMCPHighlightedIndex
            ) {
                handleSlashCommandSelectServer(serverID)
            }
            return true
        case 53:
            dismissSlashCommandPopover()
            return true
        default:
            return false
        }
    }
}
