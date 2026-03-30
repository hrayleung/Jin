import Foundation

enum ChatTimelinePayloadResolverFactory {
    static func make(messageEntitiesByID: [UUID: MessageEntity]) -> RenderedMessagePayloadResolver {
        make(contentDataByMessageID: contentDataByMessageID(messageEntitiesByID: messageEntitiesByID))
    }

    static func contentDataByMessageID(messageEntitiesByID: [UUID: MessageEntity]) -> [UUID: Data] {
        Dictionary(uniqueKeysWithValues: messageEntitiesByID.map { ($0.key, $0.value.contentData) })
    }

    static func make(contentDataByMessageID: [UUID: Data]) -> RenderedMessagePayloadResolver {
        RenderedMessagePayloadResolver(
            loadImageData: { deferredSource in
                guard let contentData = contentDataByMessageID[deferredSource.messageID] else { return nil }
                return await Task.detached(priority: .utility) {
                    HistoricalMessagePartLoader.imageData(
                        from: contentData,
                        partIndex: deferredSource.partIndex
                    )
                }.value
            },
            loadFileExtractedText: { deferredSource in
                guard let contentData = contentDataByMessageID[deferredSource.messageID] else { return nil }
                return await Task.detached(priority: .utility) {
                    HistoricalMessagePartLoader.fileExtractedText(
                        from: contentData,
                        partIndex: deferredSource.partIndex
                    )
                }.value
            }
        )
    }
}
