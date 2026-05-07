import Foundation
import SwiftData

/// Attachment entity (SwiftData)
@Model
final class AttachmentEntity {
    @Attribute(.unique) var id: UUID
    var filename: String
    var mimeType: String
    var fileURL: URL
    var uploadedAt: Date

    init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String,
        fileURL: URL,
        uploadedAt: Date = Date()
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.fileURL = fileURL
        self.uploadedAt = uploadedAt
    }
}
