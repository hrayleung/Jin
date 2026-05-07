import Foundation

extension ChatDropHandlingSupport {
    static func importAttachments(
        from urls: [URL],
        currentAttachmentCount: Int = 0,
        maxAttachments: Int? = nil
    ) async -> (attachments: [DraftAttachment], errors: [String]) {
        let plan = makeAttachmentImportPlan(
            from: urls,
            currentAttachmentCount: currentAttachmentCount,
            maxAttachments: maxAttachments
        )
        guard !plan.urlsToImport.isEmpty else {
            return ([], plan.errors)
        }

        let (newAttachments, errors) = await Task.detached(priority: .userInitiated) {
            await AttachmentImportPipeline.importInBackground(from: plan.urlsToImport)
        }.value

        return (newAttachments, plan.errors + errors)
    }

    static func makeAttachmentImportPlan(
        from urls: [URL],
        currentAttachmentCount: Int,
        maxAttachments: Int?
    ) -> AttachmentImportPlan {
        guard !urls.isEmpty else {
            return AttachmentImportPlan(urlsToImport: [], errors: [])
        }

        guard let maxAttachments else {
            return AttachmentImportPlan(urlsToImport: urls, errors: [])
        }

        let remainingSlots = max(0, maxAttachments - currentAttachmentCount)
        let limitMessage = "You can attach up to \(maxAttachments) files per message."
        guard remainingSlots > 0 else {
            return AttachmentImportPlan(urlsToImport: [], errors: [limitMessage])
        }

        let urlsToImport = Array(urls.prefix(remainingSlots))
        let errors = (urlsToImport.count < urls.count) ? [limitMessage] : []
        return AttachmentImportPlan(urlsToImport: urlsToImport, errors: errors)
    }
}
