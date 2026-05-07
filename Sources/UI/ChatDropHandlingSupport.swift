import Foundation

enum ChatDropHandlingSupport {

    struct DropResult {
        var fileURLs: [URL] = []
        var textChunks: [String] = []
        var errors: [String] = []
    }

    struct AttachmentImportPlan: Equatable {
        let urlsToImport: [URL]
        let errors: [String]
    }
}
