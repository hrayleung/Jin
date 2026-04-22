import Foundation

enum ModelContextUsageSupport {
    static func shouldShowIndicator(for modelType: ModelType?) -> Bool {
        switch modelType {
        case .image, .video:
            return false
        case .chat, nil:
            return true
        }
    }

    static func reservedOutputTokens(
        for modelType: ModelType?,
        requestedMaxTokens: Int?
    ) -> Int {
        guard shouldShowIndicator(for: modelType) else {
            return 0
        }
        return max(0, requestedMaxTokens ?? 2_048)
    }
}
