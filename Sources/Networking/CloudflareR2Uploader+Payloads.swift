import Foundation
@preconcurrency import AVFoundation

extension CloudflareR2Uploader {
    private static let xAIMaxInputVideoDurationSeconds: Double = 8.7

    private struct PreparedLocalVideoFile {
        let url: URL
        let mimeType: String
        let shouldCleanup: Bool
    }

    func localVideoPayload(from video: VideoContent) async throws -> CloudflareR2UploadPayload {
        if let data = video.data, !data.isEmpty {
            let mimeType = CloudflareR2PayloadMetadata.videoMimeType(video.mimeType, fallbackURL: video.url)
            let ext = CloudflareR2PayloadMetadata.videoFileExtension(for: mimeType, fallbackURL: video.url)
            return CloudflareR2UploadPayload(data: data, mimeType: mimeType, fileExtension: ext)
        }

        if let url = video.url {
            if url.isFileURL {
                let prepared = try await prepareLocalVideoFileForUpload(url: url, originalMIMEType: video.mimeType)
                defer {
                    if prepared.shouldCleanup {
                        try? FileManager.default.removeItem(at: prepared.url)
                    }
                }

                do {
                    let data = try Data(contentsOf: prepared.url, options: [.mappedIfSafe])
                    let mimeType = CloudflareR2PayloadMetadata.videoMimeType(prepared.mimeType, fallbackURL: prepared.url)
                    let ext = CloudflareR2PayloadMetadata.videoFileExtension(for: mimeType, fallbackURL: prepared.url)
                    return CloudflareR2UploadPayload(data: data, mimeType: mimeType, fileExtension: ext)
                } catch {
                    throw CloudflareR2UploaderError.unreadableLocalVideo(prepared.url)
                }
            }

            if url.scheme?.lowercased() == "data" {
                let parsed = try CloudflareR2DataURL(url.absoluteString)
                let mimeType = CloudflareR2PayloadMetadata.videoMimeType(parsed.mimeType ?? video.mimeType, fallbackURL: nil)
                let ext = CloudflareR2PayloadMetadata.videoFileExtension(for: mimeType, fallbackURL: nil)
                return CloudflareR2UploadPayload(data: parsed.data, mimeType: mimeType, fileExtension: ext)
            }
        }

        throw CloudflareR2UploaderError.unsupportedVideoSource
    }

    func localPDFPayload(from file: FileContent) throws -> CloudflareR2UploadPayload {
        if let data = file.data, !data.isEmpty {
            return CloudflareR2UploadPayload(
                data: data,
                mimeType: CloudflareR2PayloadMetadata.fileMimeType(file.mimeType, fallbackURL: file.url),
                fileExtension: CloudflareR2PayloadMetadata.fileExtension(for: file.mimeType, fallbackURL: file.url)
            )
        }

        if let url = file.url {
            if url.isFileURL {
                do {
                    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                    return CloudflareR2UploadPayload(
                        data: data,
                        mimeType: CloudflareR2PayloadMetadata.fileMimeType(file.mimeType, fallbackURL: url),
                        fileExtension: CloudflareR2PayloadMetadata.fileExtension(for: file.mimeType, fallbackURL: url)
                    )
                } catch {
                    throw CloudflareR2UploaderError.unreadableLocalFile(url)
                }
            }

            if url.scheme?.lowercased() == "data" {
                let parsed = try CloudflareR2DataURL(url.absoluteString)
                let mimeType = CloudflareR2PayloadMetadata.fileMimeType(parsed.mimeType ?? file.mimeType, fallbackURL: nil)
                return CloudflareR2UploadPayload(
                    data: parsed.data,
                    mimeType: mimeType,
                    fileExtension: CloudflareR2PayloadMetadata.fileExtension(for: mimeType, fallbackURL: nil)
                )
            }
        }

        throw CloudflareR2UploaderError.unsupportedFileSource
    }

    private func prepareLocalVideoFileForUpload(
        url: URL,
        originalMIMEType: String
    ) async throws -> PreparedLocalVideoFile {
        let fallbackMIMEType = CloudflareR2PayloadMetadata.videoMimeType(originalMIMEType, fallbackURL: url)

        do {
            let asset = AVURLAsset(url: url)
            let durationTime = try await asset.load(.duration)
            let duration = CMTimeGetSeconds(durationTime)
            if duration.isFinite, duration > Self.xAIMaxInputVideoDurationSeconds {
                throw CloudflareR2UploaderError.inputVideoTooLong(
                    duration: duration,
                    maximum: Self.xAIMaxInputVideoDurationSeconds
                )
            }

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard videoTracks.count > 1 else {
                return PreparedLocalVideoFile(url: url, mimeType: fallbackMIMEType, shouldCleanup: false)
            }

            return try await normalizeVideoForUpload(
                asset: asset,
                videoTrack: videoTracks[0],
                duration: durationTime
            )
        } catch let error as CloudflareR2UploaderError {
            throw error
        } catch {
            // If media introspection/export fails, keep original behavior to avoid blocking uploads.
            return PreparedLocalVideoFile(url: url, mimeType: fallbackMIMEType, shouldCleanup: false)
        }
    }

    private func normalizeVideoForUpload(
        asset: AVURLAsset,
        videoTrack: AVAssetTrack,
        duration: CMTime
    ) async throws -> PreparedLocalVideoFile {
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CloudflareR2UploaderError.unsupportedVideoSource
        }

        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoTrack,
            at: .zero
        )
        compositionVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CloudflareR2UploaderError.unsupportedVideoSource
        }

        let outputType = preferredExportFileType(for: exportSession) ?? .mp4
        let fileExtension = (outputType == .mov) ? "mov" : "mp4"
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-r2-normalized-\(UUID().uuidString).\(fileExtension)")
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputType
        exportSession.shouldOptimizeForNetworkUse = true

        try await runExportSession(exportSession)

        return PreparedLocalVideoFile(
            url: outputURL,
            mimeType: mimeType(for: outputType),
            shouldCleanup: true
        )
    }

    private func runExportSession(_ exportSession: AVAssetExportSession) async throws {
        let boxedSession = ExportSessionBox(exportSession)
        try await withCheckedThrowingContinuation { continuation in
            boxedSession.session.exportAsynchronously {
                switch boxedSession.session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(
                        throwing: boxedSession.session.error ?? CloudflareR2UploaderError.unsupportedVideoSource
                    )
                case .cancelled:
                    continuation.resume(
                        throwing: boxedSession.session.error
                            ?? CloudflareR2UploaderError.publicURLValidationFailed(message: "Video normalization was cancelled.")
                    )
                default:
                    continuation.resume(
                        throwing: boxedSession.session.error ?? CloudflareR2UploaderError.unsupportedVideoSource
                    )
                }
            }
        }
    }

    private func preferredExportFileType(for exportSession: AVAssetExportSession) -> AVFileType? {
        if exportSession.supportedFileTypes.contains(.mp4) {
            return .mp4
        }
        if exportSession.supportedFileTypes.contains(.mov) {
            return .mov
        }
        return exportSession.supportedFileTypes.first
    }

    private func mimeType(for fileType: AVFileType) -> String {
        switch fileType {
        case .mp4:
            return "video/mp4"
        case .mov:
            return "video/quicktime"
        default:
            return "video/mp4"
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
