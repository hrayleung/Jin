import AppKit
import Foundation
import PDFKit

enum PDFKitImageRenderer {
    struct RenderedImage: Sendable {
        let pageIndex: Int
        let mimeType: String
        let data: Data
        let pixelSize: CGSize
    }

    enum RenderError: Error, LocalizedError {
        case failedToLoadPDF
        case pageOutOfRange(index: Int)
        case failedToEncodeImage

        var errorDescription: String? {
            switch self {
            case .failedToLoadPDF:
                return "Failed to load PDF."
            case .pageOutOfRange(let index):
                return "PDF page index out of range: \(index)."
            case .failedToEncodeImage:
                return "Failed to encode rendered PDF page image."
            }
        }
    }

    static func renderAllPagesAsJPEG(
        from url: URL,
        maxDimension: CGFloat = 2560,
        quality: CGFloat = 0.85,
        maxBytesPerPage: Int = 3_000_000,
        maxPages: Int? = nil
    ) throws -> [RenderedImage] {
        guard let document = PDFDocument(url: url) else {
            throw RenderError.failedToLoadPDF
        }

        let totalPages = document.pageCount
        let limit = maxPages.map { min($0, totalPages) } ?? totalPages
        guard limit > 0 else { return [] }

        var output: [RenderedImage] = []
        output.reserveCapacity(limit)

        for index in 0..<limit {
            guard let page = document.page(at: index) else {
                throw RenderError.pageOutOfRange(index: index)
            }
            let rendered = try renderPageAsJPEG(
                page,
                pageIndex: index,
                maxDimension: maxDimension,
                quality: quality,
                maxBytes: maxBytesPerPage
            )
            output.append(rendered)
        }

        return output
    }

    static func renderPageAsJPEG(
        from url: URL,
        pageIndex: Int,
        maxDimension: CGFloat = 2560,
        quality: CGFloat = 0.85,
        maxBytes: Int = 3_000_000
    ) throws -> RenderedImage {
        guard let document = PDFDocument(url: url) else {
            throw RenderError.failedToLoadPDF
        }
        guard let page = document.page(at: pageIndex) else {
            throw RenderError.pageOutOfRange(index: pageIndex)
        }
        return try renderPageAsJPEG(
            page,
            pageIndex: pageIndex,
            maxDimension: maxDimension,
            quality: quality,
            maxBytes: maxBytes
        )
    }

    // MARK: - Private

    private static func renderPageAsJPEG(
        _ page: PDFPage,
        pageIndex: Int,
        maxDimension: CGFloat,
        quality: CGFloat,
        maxBytes: Int
    ) throws -> RenderedImage {
        let bounds = page.bounds(for: .mediaBox)
        let largestSide = max(bounds.width, bounds.height)
        let scale = (largestSide > 0) ? (maxDimension / largestSide) : 1

        var currentMaxDimension = max(768, maxDimension)
        var currentQuality = min(0.95, max(0.5, quality))

        for _ in 0..<8 {
            let renderScale = (largestSide > 0) ? (currentMaxDimension / largestSide) : 1
            let targetSize = CGSize(width: max(1, bounds.width * renderScale), height: max(1, bounds.height * renderScale))
            let image = page.thumbnail(of: targetSize, for: .mediaBox)

            if let data = encodeJPEG(image, quality: currentQuality) {
                if data.count <= maxBytes {
                    return RenderedImage(
                        pageIndex: pageIndex,
                        mimeType: "image/jpeg",
                        data: data,
                        pixelSize: targetSize
                    )
                }
            }

            currentMaxDimension = max(768, currentMaxDimension * 0.82)
            currentQuality = max(0.6, currentQuality - 0.08)
        }

        // Final attempt: return best-effort, even if above maxBytes, to avoid hard-failing OCR.
        let finalScale = (largestSide > 0) ? (currentMaxDimension / largestSide) : scale
        let finalSize = CGSize(width: max(1, bounds.width * finalScale), height: max(1, bounds.height * finalScale))
        let finalImage = page.thumbnail(of: finalSize, for: .mediaBox)
        guard let finalData = encodeJPEG(finalImage, quality: currentQuality) else {
            throw RenderError.failedToEncodeImage
        }

        return RenderedImage(
            pageIndex: pageIndex,
            mimeType: "image/jpeg",
            data: finalData,
            pixelSize: finalSize
        )
    }

    private static func encodeJPEG(_ image: NSImage, quality: CGFloat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }

        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}

