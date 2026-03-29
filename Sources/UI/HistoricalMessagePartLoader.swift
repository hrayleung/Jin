import Foundation

enum HistoricalMessagePartLoader {
    static func imageData(from contentData: Data, partIndex: Int) -> Data? {
        guard let parts = try? JSONDecoder().decode([ContentPart].self, from: contentData),
              parts.indices.contains(partIndex),
              case .image(let image) = parts[partIndex] else {
            return nil
        }

        return image.data
    }

    static func fileExtractedText(from contentData: Data, partIndex: Int) -> String? {
        guard let parts = try? JSONDecoder().decode([ContentPart].self, from: contentData),
              parts.indices.contains(partIndex),
              case .file(let file) = parts[partIndex] else {
            return nil
        }

        return file.extractedText
    }
}
