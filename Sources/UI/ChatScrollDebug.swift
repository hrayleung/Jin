import Foundation
import os

enum ChatScrollDebug {
    private static let logger = Logger(subsystem: "com.jin.app", category: "ChatScroll")

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    static func shortID(_ id: UUID?) -> String {
        guard let id else { return "nil" }
        return String(id.uuidString.prefix(8))
    }
}
