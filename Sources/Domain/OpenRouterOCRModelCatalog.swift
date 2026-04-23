import Foundation

enum OpenRouterOCRModelCatalog {
    struct Entry: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let detail: String
    }

    static let entries: [Entry] = [
        Entry(
            id: "baidu/qianfan-ocr-fast:free",
            name: "Qianfan OCR Fast (free)",
            detail: "Baidu OCR-specialized model."
        ),
        Entry(
            id: "z-ai/glm-4.6v",
            name: "GLM 4.6V",
            detail: "Z.ai document and mixed-media vision model."
        ),
        Entry(
            id: "qwen/qwen3-vl-8b-instruct",
            name: "Qwen3 VL 8B Instruct",
            detail: "Qwen multimodal vision-language model."
        ),
        Entry(
            id: "qwen/qwen2.5-vl-72b-instruct",
            name: "Qwen2.5 VL 72B Instruct",
            detail: "Qwen document, chart, and layout understanding."
        ),
        Entry(
            id: "mistralai/pixtral-large-2411",
            name: "Pixtral Large 2411",
            detail: "Mistral document and chart vision model."
        )
    ]

    static var defaultEntry: Entry {
        entries[0]
    }

    static var defaultModelID: String {
        defaultEntry.id
    }

    static func entry(for id: String?) -> Entry? {
        guard let normalized = id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }
        return entries.first { $0.id == normalized }
    }

    static func resolvedEntry(for id: String?) -> Entry {
        entry(for: id) ?? defaultEntry
    }

    static func normalizedModelID(_ id: String?) -> String {
        resolvedEntry(for: id).id
    }
}
