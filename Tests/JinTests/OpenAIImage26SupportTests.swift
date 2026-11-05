import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Jin

final class OpenAIImage26SupportTests: XCTestCase {
    private let ids = ["gpt-image-2.6-flare", "gpt-image-2.6-sunburst"]

    func testExactCatalogSeedsInferenceAndLegacySettings() throws {
        for id in ids {
            let info = ModelCatalog.modelInfo(for: id, provider: .openai)
            XCTAssertEqual(info.capabilities, [.vision, .imageGeneration])
            XCTAssertEqual(info.contextWindow, 0)
            XCTAssertNil(info.maxOutputTokens)
            XCTAssertTrue(ModelCatalog.seededModels(for: .openai).contains { $0.id == id })
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openai, modelID: id))
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openaiWebSocket, modelID: id))
            XCTAssertTrue(ModelCatalog.seededModels(for: .openaiWebSocket).contains { $0.id == id })
            XCTAssertTrue(OpenAIAdapter.imageGenerationModelIDs.contains(id))
            XCTAssertTrue(OpenAIAdapter.imageEditSupportedModelIDs.contains(id))
            let legacy = ModelInfo(id: id, name: id, capabilities: [.streaming, .reasoning], contextWindow: 128_000, maxOutputTokens: 4_096)
            let settings = ModelSettingsResolver.resolve(model: legacy, providerType: .openai)
            XCTAssertEqual(settings.capabilities, info.capabilities)
            XCTAssertEqual(settings.contextWindow, 0)
            XCTAssertNil(settings.maxOutputTokens)
            XCTAssertNil(settings.reasoningConfig)
            XCTAssertEqual(settings.modelType, .image)
            XCTAssertFalse(settings.supportsWebSearch)
            let profile = try XCTUnwrap(OpenAIImageModelSupport.profile(for: id))
            XCTAssertTrue(profile.supportsComplexity)
            XCTAssertTrue(profile.supportsEditGuidance)
            XCTAssertTrue(profile.usesMultipartEdits)
            XCTAssertEqual(profile.outputFormats, [.png, .jpeg, .webp, .svg, .gif])
            XCTAssertEqual(profile.qualityOptions, [.auto, .low, .medium, .high, .xhigh, .max])
            XCTAssertFalse(profile.supportsInputFidelity)
        }
        for id in ["gpt-image-2.6", "gpt-image-2.6-flare-custom", "gpt-image-2.6-sunburst-2026-11-05", "openai/gpt-image-2.6-flare"] {
            XCTAssertNil(OpenAIImageModelSupport.profile(for: id))
            XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openai, modelID: id))
        }
    }

    func testRasterAndAnimationDimensionRulesAreDistinct() {
        for id in ids {
            for size in ["auto", "1024x1024", "1536x864", "3840x2160", "2160x3840"] {
                XCTAssertNil(OpenAIImageModelSupport.validate(size: .init(rawValue: size), for: id), size)
            }
            for size in ["512x512", "2049x1024", "4000x2000", "3840x3840", "3072x768", "0x0"] {
                XCTAssertNotNil(OpenAIImageModelSupport.validate(size: .init(rawValue: size), for: id), size)
            }
            XCTAssertNil(OpenAIImageCustomSizeSheetSupport.validationError(draftText: "512x512", modelID: id, outputFormat: .gif))
            XCTAssertNotNil(OpenAIImageCustomSizeSheetSupport.validationError(draftText: "513x512", modelID: id, outputFormat: .gif))
        }
    }

    func testControlPersistenceAndOldConversationDefaults() throws {
        let options = OpenAIImageGenerationControls(quality: .max, outputFormat: .gif, complexity: .medium,
            frameCount: 17, frameDurationMilliseconds: 120, inputMode: .generate)
        let stored = try JSONEncoder().encode(GenerationControls(openaiImageGeneration: options))
        let loaded = try JSONDecoder().decode(GenerationControls.self, from: stored).openaiImageGeneration
        XCTAssertEqual(loaded?.quality, .max)
        XCTAssertEqual(loaded?.outputFormat, .gif)
        XCTAssertEqual(loaded?.complexity, .medium)
        XCTAssertEqual(loaded?.frameCount, 17)
        XCTAssertEqual(loaded?.frameDurationMilliseconds, 120)
        XCTAssertEqual(loaded?.inputMode, .generate)
        let legacy = try JSONDecoder().decode(OpenAIImageGenerationControls.self, from: Data(#"{"quality":"high","size":"1024x1024"}"#.utf8))
        XCTAssertNil(legacy.inputMode)
        XCTAssertNil(legacy.editGuidance)
        XCTAssertNil(legacy.complexity)
        XCTAssertNil(legacy.frameCount)
        for guidance in OpenAIImageEditGuidance.allCases {
            let edit = OpenAIImageGenerationControls(complexity: .low, inputMode: .edit, editGuidance: guidance)
            let restored = try JSONDecoder().decode(OpenAIImageGenerationControls.self, from: JSONEncoder().encode(edit))
            XCTAssertEqual(restored.editGuidance, guidance)
            XCTAssertEqual(restored.inputMode, .edit)
        }
    }

    func testNormalizationKeepsOnlySupportedControlsWhenSwitchingModelsAndFormats() {
        var options = OpenAIImageGenerationControls(count: 4, outputFormat: .gif, outputCompression: 50,
            complexity: .low, frameCount: 100, frameDurationMilliseconds: 155, inputMode: .generate)
        OpenAIImageModelSupport.normalize(&options, for: ids[0])
        XCTAssertEqual(options.frameCount, 64)
        XCTAssertEqual(options.frameDurationMilliseconds, 160)
        XCTAssertNil(options.outputCompression)
        options.outputFormat = .svg
        OpenAIImageModelSupport.normalize(&options, for: ids[0])
        XCTAssertEqual(options.count, 1)
        XCTAssertNil(options.frameCount)
        XCTAssertNil(options.frameDurationMilliseconds)
        options.editGuidance = .markup
        OpenAIImageModelSupport.normalize(&options, for: "gpt-image-2.5-flare")
        XCTAssertNil(options.outputFormat)
        XCTAssertNil(options.complexity)
        XCTAssertNil(options.editGuidance)
        XCTAssertNil(options.inputMode)
        XCTAssertEqual(OpenAIImageModelSupport.profile(for: "gpt-image-2.5-flare")?.outputFormats, [.png, .jpeg, .webp])
    }

    func testMarkupRequiresSeparateTransparentPNGWithMatchingDimensions() throws {
        let original = try Self.png(width: 32, height: 16, alpha: 1)
        let overlay = try Self.png(width: 32, height: 16, alpha: 0.2)
        XCTAssertNoThrow(try OpenAIImageEditValidation.validateGuide(overlay, original: original, kind: .markup))
        XCTAssertThrowsError(try OpenAIImageEditValidation.validateGuide(original, original: original, kind: .markup))
        XCTAssertThrowsError(try OpenAIImageEditValidation.validateGuide(Self.png(width: 16, height: 16, alpha: 0), original: original, kind: .markup))
        XCTAssertThrowsError(try OpenAIImageEditValidation.raster(Data("not an image".utf8)))
        XCTAssertThrowsError(try OpenAIImageEditValidation.raster(Self.svg))
    }

    func testMaskSupportsTransparentRegionsAndOpaqueAlpha() throws {
        let original = try Self.png(width: 32, height: 32, alpha: 1)
        XCTAssertNoThrow(try OpenAIImageEditValidation.validateGuide(original, original: original, kind: .mask))
        XCTAssertNoThrow(try OpenAIImageEditValidation.validateGuide(Self.png(width: 32, height: 32, alpha: 0), original: original, kind: .mask))
        XCTAssertThrowsError(try OpenAIImageEditValidation.validateGuide(Self.png(width: 16, height: 32, alpha: 0), original: original, kind: .mask))
    }

    func testSVGNativePreviewAndSafeVectorValidation() throws {
        XCTAssertNoThrow(try OpenAIImageSVGValidation.validate(Self.svg))
        let preview = try XCTUnwrap(SVGImagePreviewSupport.image(data: Self.svg, maxPixelSize: 120))
        XCTAssertGreaterThan(preview.size.width, 0)
        let documents = [
            #"<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><image href="https://example.com/a.png"/></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><use href="https://example.com/a.svg#x"/></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><rect onclick="alert(1)"/></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><style>rect{fill:url( https://example.com/a )}</style></svg>"#,
            #"<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///etc/passwd">]><svg>&x;</svg>"#,
            #"<svg><g>"#
        ]
        for document in documents { XCTAssertThrowsError(try OpenAIImageSVGValidation.validate(Data(document.utf8))) }
    }

    func testSVGAndGIFPersistencePreservesOriginalBytesAndExtensions() throws {
        for (data, mime, ext) in [(Self.svg, "image/svg+xml", "svg"), (try Self.gif(), "image/gif", "gif")] {
            let preview = try XCTUnwrap(NSImage(data: data))
            let file = try XCTUnwrap(MessageMediaAssetPersistenceSupport.persistImageToDisk(data: data, image: preview, mimeType: mime))
            defer { try? FileManager.default.removeItem(at: file) }
            XCTAssertEqual(file.pathExtension, ext)
            XCTAssertEqual(try Data(contentsOf: file), data)
            XCTAssertEqual(inferImageMIMEType(from: file), mime)
        }
    }

    func testAnimatedPreviewRetainsFramesAndTimingAtBoundedSize() throws {
        let data = try Self.gif()
        let preview = try XCTUnwrap(AnimatedImagePreviewSupport.image(data: data, maxPixelSize: 24))
        let bitmap = try XCTUnwrap(preview.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(bitmap.value(forProperty: .frameCount) as? Int, 3)
        XCTAssertLessThanOrEqual(bitmap.pixelsWide, 24)
        XCTAssertEqual(bitmap.value(forProperty: .currentFrameDuration) as? Double ?? 0, 0.2, accuracy: 0.001)
    }

    func testGeneratedConversationAttachmentsKeepSVGAndGIFBytes() async throws {
        for (data, mime, ext) in [(Self.svg, "image/svg+xml", "svg"), (try Self.gif(), "image/gif", "gif")] {
            let parts = await AttachmentImportPipeline.persistImagesToDisk([
                .image(ImageContent(mimeType: mime, data: data, url: nil))
            ])
            guard case .image(let stored)? = parts.first else { return XCTFail("Missing stored image") }
            let file = try XCTUnwrap(stored.url)
            defer { try? FileManager.default.removeItem(at: file) }
            XCTAssertEqual(file.pathExtension, ext)
            XCTAssertEqual(stored.mimeType, mime)
            XCTAssertEqual(stored.assetDisposition, .managed)
            XCTAssertNil(stored.data)
            XCTAssertEqual(try Data(contentsOf: file), data)
        }
    }

    static let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="60"><defs><linearGradient id="a"><stop stop-color="red"/></linearGradient></defs><rect width="100" height="60" fill="url(#a)"/></svg>"#.utf8)

    static func png(width: Int = 32, height: Int = 32, alpha: CGFloat = 1) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.8, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func gif() throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 3, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for alpha in [CGFloat(1), 0.5, 0.2] {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(png(alpha: alpha) as CFData, nil))
            CGImageDestinationAddImageFromSource(destination, source, 0,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
