import Foundation

enum PDFProcessingError: Error, LocalizedError {
    case mistralAPIKeyMissing
    case deepInfraAPIKeyMissing
    case nativePDFNotSupported(modelName: String)
    case fileReadFailed(filename: String)
    case noTextExtracted(filename: String, method: String)

    var errorDescription: String? {
        switch self {
        case .mistralAPIKeyMissing:
            return "Mistral OCR API key is not configured. Set it in Settings → Plugins → Mistral OCR."
        case .deepInfraAPIKeyMissing:
            return "DeepSeek OCR (DeepInfra) API key is not configured. Set it in Settings → Plugins → DeepSeek OCR (DeepInfra)."
        case .nativePDFNotSupported(let modelName):
            return "“\(modelName)” does not support native PDF reading. Choose Mistral OCR, DeepSeek OCR (DeepInfra), or macOS Extract in the PDF menu."
        case .fileReadFailed(let filename):
            return "Failed to read “\(filename)”."
        case .noTextExtracted(let filename, let method):
            return "No text could be extracted from “\(filename)” using \(method)."
        }
    }
}
