import Foundation

struct ChatSendDraftSnapshot: Sendable {
    let messageText: String
    let remoteVideoURLText: String
    let attachments: [DraftAttachment]
    let quotes: [DraftQuote]
    let perMessageMCPServerIDs: Set<String>
    let perMessageMCPServerNames: [String]
    let perMessageMCPServerIDsData: Data?
    let askedAt: Date

    var quoteContents: [QuoteContent] {
        quotes.map(\.content)
    }

    init(
        messageText: String,
        remoteVideoURLText: String,
        attachments: [DraftAttachment],
        quotes: [DraftQuote],
        selectedPerMessageMCPServers: [(id: String, name: String)],
        askedAt: Date = Date()
    ) {
        let selectedServers = selectedPerMessageMCPServers.sorted {
            if $0.id == $1.id {
                return $0.name < $1.name
            }
            return $0.id < $1.id
        }
        let selectedIDs = selectedServers.map(\.id)
        self.messageText = messageText
        self.remoteVideoURLText = remoteVideoURLText
        self.attachments = attachments
        self.quotes = quotes
        self.perMessageMCPServerIDs = Set(selectedIDs)
        self.perMessageMCPServerNames = selectedServers.map(\.name)
        self.perMessageMCPServerIDsData = selectedIDs.isEmpty ? nil : try? JSONEncoder().encode(selectedIDs)
        self.askedAt = askedAt
    }
}

@MainActor
enum ChatUserTurnPersistence {
    static func appendPreparedUserMessage(
        parts: [ContentPart],
        draft: ChatSendDraftSnapshot,
        toolCapable: Bool,
        conversationEntity: ConversationEntity,
        isChatNamingPluginEnabled: Bool,
        persistConversationIfNeeded: () -> Void,
        makeConversationTitle: (String) -> String,
        rebuildMessageCaches: () -> Void
    ) {
        if conversationEntity.messages.isEmpty {
            persistConversationIfNeeded()
        }

        let message = Message(
            role: .user,
            content: parts,
            timestamp: draft.askedAt,
            perMessageMCPServerNames: toolCapable ? draft.perMessageMCPServerNames : nil
        )
        let messageEntity: MessageEntity
        do {
            messageEntity = try MessageEntity.fromDomain(message)
        } catch {
            NSLog(
                "Jin user turn persistence warning: failed to persist prepared user message. conversationID=%@ error=%@",
                conversationEntity.id.uuidString,
                error.localizedDescription
            )
            return
        }
        if toolCapable {
            messageEntity.perMessageMCPServerIDsData = draft.perMessageMCPServerIDsData
        }
        messageEntity.conversation = conversationEntity
        conversationEntity.messages.append(messageEntity)

        applyFallbackTitleIfNeeded(
            draft: draft,
            conversationEntity: conversationEntity,
            isChatNamingPluginEnabled: isChatNamingPluginEnabled,
            makeConversationTitle: makeConversationTitle
        )
        conversationEntity.updatedAt = draft.askedAt
        rebuildMessageCaches()
    }

    private static func applyFallbackTitleIfNeeded(
        draft: ChatSendDraftSnapshot,
        conversationEntity: ConversationEntity,
        isChatNamingPluginEnabled: Bool,
        makeConversationTitle: (String) -> String
    ) {
        guard conversationEntity.title == "New Chat", !isChatNamingPluginEnabled else { return }

        if !draft.messageText.isEmpty {
            conversationEntity.title = makeConversationTitle(draft.messageText)
        } else if let firstQuote = draft.quotes.first {
            conversationEntity.title = makeConversationTitle(firstQuote.content.quotedText)
        } else if let firstAttachment = draft.attachments.first {
            conversationEntity.title = makeConversationTitle((firstAttachment.filename as NSString).deletingPathExtension)
        }
    }
}
