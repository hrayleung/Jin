import Foundation
import CryptoKit
@preconcurrency import AVFoundation

struct CloudflareR2Configuration: Equatable {
    let accountID: String
    let accessKeyID: String
    let secretAccessKey: String
    let bucket: String
    let publicBaseURL: String
    let keyPrefix: String

    init(
        accountID: String,
        accessKeyID: String,
        secretAccessKey: String,
        bucket: String,
        publicBaseURL: String,
        keyPrefix: String
    ) {
        self.accountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accessKeyID = accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secretAccessKey = secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bucket = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        self.publicBaseURL = publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.keyPrefix = keyPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func load(from defaults: UserDefaults = .standard) -> CloudflareR2Configuration {
        CloudflareR2Configuration(
            accountID: defaults.string(forKey: AppPreferenceKeys.cloudflareR2AccountID) ?? "",
            accessKeyID: defaults.string(forKey: AppPreferenceKeys.cloudflareR2AccessKeyID) ?? "",
            secretAccessKey: defaults.string(forKey: AppPreferenceKeys.cloudflareR2SecretAccessKey) ?? "",
            bucket: defaults.string(forKey: AppPreferenceKeys.cloudflareR2Bucket) ?? "",
            publicBaseURL: defaults.string(forKey: AppPreferenceKeys.cloudflareR2PublicBaseURL) ?? "",
            keyPrefix: defaults.string(forKey: AppPreferenceKeys.cloudflareR2KeyPrefix) ?? ""
        )
    }

    var missingRequiredFields: [String] {
        var out: [String] = []
        if accountID.isEmpty { out.append("Account ID") }
        if accessKeyID.isEmpty { out.append("Access Key ID") }
        if secretAccessKey.isEmpty { out.append("Secret Access Key") }
        if bucket.isEmpty { out.append("Bucket") }
        if publicBaseURL.isEmpty { out.append("Public Base URL") }
        return out
    }

    var normalizedKeyPrefix: String? {
        let trimmed = keyPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? nil : trimmed
    }

    var uploadHost: String {
        "\(accountID).r2.cloudflarestorage.com"
    }

    func validated() throws -> CloudflareR2Configuration {
        let missing = missingRequiredFields
        guard missing.isEmpty else {
            throw CloudflareR2UploaderError.missingConfiguration(fields: missing)
        }

        guard var components = URLComponents(string: publicBaseURL),
              let scheme = components.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              components.host?.isEmpty == false,
              components.query?.isEmpty ?? true,
              components.fragment?.isEmpty ?? true else {
            throw CloudflareR2UploaderError.invalidPublicBaseURL(publicBaseURL)
        }

        let normalizedPath = components.percentEncodedPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = normalizedPath.isEmpty ? "" : "/\(normalizedPath)"

        guard components.url != nil else {
            throw CloudflareR2UploaderError.invalidPublicBaseURL(publicBaseURL)
        }
        return self
    }

    func publicURL(for objectKey: String) throws -> URL {
        guard var components = URLComponents(string: publicBaseURL),
              let scheme = components.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              components.host?.isEmpty == false else {
            throw CloudflareR2UploaderError.invalidPublicBaseURL(publicBaseURL)
        }

        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedKey = objectKey
            .split(separator: "/")
            .map { R2Signing.percentEncodePathSegment(String($0)) }
            .joined(separator: "/")

        if basePath.isEmpty {
            components.percentEncodedPath = "/\(encodedKey)"
        } else {
            components.percentEncodedPath = "/\(basePath)/\(encodedKey)"
        }
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw CloudflareR2UploaderError.invalidPublicBaseURL(publicBaseURL)
        }
        return url
    }
}

enum CloudflareR2UploaderError: LocalizedError {
    case missingConfiguration(fields: [String])
    case invalidPublicBaseURL(String)
    case unsupportedVideoSource
    case unreadableLocalVideo(URL)
    case malformedDataURL
    case uploadRejected(statusCode: Int, message: String)
    case publicURLValidationFailed(message: String)
    case inputVideoTooLong(duration: Double, maximum: Double)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let fields):
            return "Missing Cloudflare R2 settings: \(fields.joined(separator: ", "))."
        case .invalidPublicBaseURL(let value):
            return "Invalid Cloudflare R2 public base URL: \(value). Use an http(s) URL without query parameters."
        case .unsupportedVideoSource:
            return "Unsupported video input. Use a local file/video attachment or an HTTPS URL."
        case .unreadableLocalVideo(let url):
            return "Could not read local video file: \(url.path)."
        case .malformedDataURL:
            return "Invalid data URL for video input."
        case .uploadRejected(let statusCode, let message):
            return "Cloudflare R2 upload failed (HTTP \(statusCode)): \(message)"
        case .publicURLValidationFailed(let message):
            return "Cloudflare R2 public URL validation failed: \(message)"
        case .inputVideoTooLong(let duration, let maximum):
            return "Input video is too long for xAI video edit (\(String(format: "%.2f", duration))s). Maximum supported length is \(String(format: "%.1f", maximum))s."
        }
    }
}

actor CloudflareR2Uploader {
    private static let xAIMaxInputVideoDurationSeconds: Double = 8.7

    private let networkManager: NetworkManager
    private let defaults: UserDefaults

    init(networkManager: NetworkManager = NetworkManager(), defaults: UserDefaults = .standard) {
        self.networkManager = networkManager
        self.defaults = defaults
    }

    func currentConfiguration() -> CloudflareR2Configuration {
        CloudflareR2Configuration.load(from: defaults)
    }

    func isPluginEnabled() -> Bool {
        AppPreferences.isPluginEnabled("cloudflare_r2_upload", defaults: defaults)
    }

    func uploadVideo(
        _ video: VideoContent,
        configuration overrideConfiguration: CloudflareR2Configuration? = nil
    ) async throws -> URL {
        let configuration = try (overrideConfiguration ?? currentConfiguration()).validated()
        let payload = try await localVideoPayload(from: video)
        let objectKey = makeObjectKey(prefix: configuration.normalizedKeyPrefix, fileExtension: payload.fileExtension)

        let request = try signedRequest(
            method: "PUT",
            configuration: configuration,
            objectKey: objectKey,
            payloadData: payload.data,
            contentType: payload.mimeType
        )
        let (responseData, response) = try await networkManager.sendRawRequest(request)
        guard (200..<300).contains(response.statusCode) else {
            throw CloudflareR2UploaderError.uploadRejected(
                statusCode: response.statusCode,
                message: Self.previewString(from: responseData)
            )
        }

        let publicURL = try configuration.publicURL(for: objectKey)
        try await validatePublicVideoURL(publicURL)
        return publicURL
    }

    func testConnection(configuration overrideConfiguration: CloudflareR2Configuration? = nil) async throws {
        let configuration = try (overrideConfiguration ?? currentConfiguration()).validated()
        let key = makeObjectKey(prefix: configuration.normalizedKeyPrefix, fileExtension: "txt", namespace: "jin-r2-test")
        let payload = Data("jin-r2-connection-test".utf8)

        let putRequest = try signedRequest(
            method: "PUT",
            configuration: configuration,
            objectKey: key,
            payloadData: payload,
            contentType: "text/plain"
        )
        let (putResponseData, putResponse) = try await networkManager.sendRawRequest(putRequest)
        guard (200..<300).contains(putResponse.statusCode) else {
            throw CloudflareR2UploaderError.uploadRejected(
                statusCode: putResponse.statusCode,
                message: Self.previewString(from: putResponseData)
            )
        }

        do {
            let deleteRequest = try signedRequest(
                method: "DELETE",
                configuration: configuration,
                objectKey: key,
                payloadData: Data(),
                contentType: nil
            )
            _ = try await networkManager.sendRawRequest(deleteRequest)
        } catch {
            // Ignore cleanup failures (missing DeleteObject permission is common).
        }
    }

    private struct LocalVideoPayload {
        let data: Data
        let mimeType: String
        let fileExtension: String
    }

    private struct PreparedLocalVideoFile {
        let url: URL
        let mimeType: String
        let shouldCleanup: Bool
    }

    private func localVideoPayload(from video: VideoContent) async throws -> LocalVideoPayload {
        if let data = video.data, !data.isEmpty {
            let mimeType = normalizedMimeType(video.mimeType, fallbackURL: video.url)
            let ext = fileExtension(for: mimeType, fallbackURL: video.url)
            return LocalVideoPayload(data: data, mimeType: mimeType, fileExtension: ext)
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
                    let mimeType = normalizedMimeType(prepared.mimeType, fallbackURL: prepared.url)
                    let ext = fileExtension(for: mimeType, fallbackURL: prepared.url)
                    return LocalVideoPayload(data: data, mimeType: mimeType, fileExtension: ext)
                } catch {
                    throw CloudflareR2UploaderError.unreadableLocalVideo(prepared.url)
                }
            }

            if url.scheme?.lowercased() == "data" {
                let parsed = try parseDataURL(url.absoluteString)
                let mimeType = normalizedMimeType(parsed.mimeType ?? video.mimeType, fallbackURL: nil)
                let ext = fileExtension(for: mimeType, fallbackURL: nil)
                return LocalVideoPayload(data: parsed.data, mimeType: mimeType, fileExtension: ext)
            }
        }

        throw CloudflareR2UploaderError.unsupportedVideoSource
    }

    private func prepareLocalVideoFileForUpload(url: URL, originalMIMEType: String) async throws -> PreparedLocalVideoFile {
        let fallbackMIMEType = normalizedMimeType(originalMIMEType, fallbackURL: url)

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

            let normalized = try await normalizeVideoForUpload(
                asset: asset,
                videoTrack: videoTracks[0],
                duration: durationTime
            )
            return normalized
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

    private func parseDataURL(_ value: String) throws -> (mimeType: String?, data: Data) {
        guard value.lowercased().hasPrefix("data:"),
              let commaIndex = value.firstIndex(of: ",") else {
            throw CloudflareR2UploaderError.malformedDataURL
        }

        let metadataRange = value.index(value.startIndex, offsetBy: 5)..<commaIndex
        let payloadRange = value.index(after: commaIndex)..<value.endIndex
        let metadata = String(value[metadataRange])
        let payload = String(value[payloadRange])

        let metadataParts = metadata.split(separator: ";").map(String.init)
        let mimeType = metadataParts.first(where: { !$0.isEmpty })
        let isBase64 = metadataParts.contains(where: { $0.caseInsensitiveCompare("base64") == .orderedSame })

        if isBase64 {
            guard let data = Data(base64Encoded: payload) else {
                throw CloudflareR2UploaderError.malformedDataURL
            }
            return (mimeType, data)
        }

        guard let decoded = payload.removingPercentEncoding,
              let data = decoded.data(using: .utf8) else {
            throw CloudflareR2UploaderError.malformedDataURL
        }
        return (mimeType, data)
    }

    private func normalizedMimeType(_ mimeType: String, fallbackURL: URL?) -> String {
        let trimmed = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            return trimmed
        }

        if let fallbackURL {
            switch fallbackURL.pathExtension.lowercased() {
            case "mov": return "video/quicktime"
            case "webm": return "video/webm"
            case "avi": return "video/x-msvideo"
            case "mkv": return "video/x-matroska"
            default: return "video/mp4"
            }
        }
        return "video/mp4"
    }

    private func fileExtension(for mimeType: String, fallbackURL: URL?) -> String {
        switch mimeType.lowercased() {
        case "video/quicktime":
            return "mov"
        case "video/webm":
            return "webm"
        case "video/x-msvideo":
            return "avi"
        case "video/x-matroska":
            return "mkv"
        case "video/mp4":
            return "mp4"
        default:
            if let fallback = fallbackURL?.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines),
               !fallback.isEmpty {
                return fallback.lowercased()
            }
            return "mp4"
        }
    }

    private func makeObjectKey(prefix: String?, fileExtension: String, namespace: String = "jin-videos") -> String {
        let day = Self.dayStamp(from: Date())
        var segments: [String] = []

        if let prefix, !prefix.isEmpty {
            segments.append(contentsOf: prefix.split(separator: "/").map(String.init))
        }

        segments.append(namespace)
        segments.append(day)
        segments.append("\(UUID().uuidString).\(fileExtension)")
        return segments.joined(separator: "/")
    }

    private func signedRequest(
        method: String,
        configuration: CloudflareR2Configuration,
        objectKey: String,
        payloadData: Data,
        contentType: String?
    ) throws -> URLRequest {
        let amzDate = Self.amzDateString(from: Date())
        let dateStamp = String(amzDate.prefix(8))
        let credentialScope = "\(dateStamp)/auto/s3/aws4_request"

        let canonicalURI = R2Signing.canonicalURI(bucket: configuration.bucket, objectKey: objectKey)
        let canonicalQuery = ""
        let payloadHash = R2Signing.sha256Hex(payloadData)

        var headers: [String: String] = [
            "host": configuration.uploadHost,
            "x-amz-content-sha256": payloadHash,
            "x-amz-date": amzDate
        ]
        if let contentType, !contentType.isEmpty {
            headers["content-type"] = contentType
        }

        let sortedHeaderNames = headers.keys.sorted()
        let canonicalHeaders = sortedHeaderNames
            .map { "\($0):\(headers[$0]!.trimmingCharacters(in: .whitespacesAndNewlines))\n" }
            .joined()
        let signedHeaders = sortedHeaderNames.joined(separator: ";")

        let canonicalRequest = [
            method.uppercased(),
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            R2Signing.sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        let signingKey = R2Signing.signingKey(
            secretAccessKey: configuration.secretAccessKey,
            dateStamp: dateStamp,
            region: "auto",
            service: "s3"
        )
        let signature = R2Signing.hmacHex(key: signingKey, message: stringToSign)

        let authorization = "AWS4-HMAC-SHA256 Credential=\(configuration.accessKeyID)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var components = URLComponents()
        components.scheme = "https"
        components.host = configuration.uploadHost
        components.percentEncodedPath = canonicalURI

        guard let url = components.url else {
            throw LLMError.invalidRequest(message: "Failed to build Cloudflare R2 request URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        request.httpBody = payloadData.isEmpty ? nil : payloadData
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    private func validatePublicVideoURL(_ url: URL) async throws {
        let retryDelays: [UInt64] = [
            0,
            250_000_000,
            500_000_000,
            1_000_000_000
        ]

        var lastMessage = "Unknown validation failure."

        for delay in retryDelays {
            if delay > 0 {
                try await Task.sleep(nanoseconds: delay)
            }

            do {
                try await validatePublicVideoURLOnce(url)
                return
            } catch {
                lastMessage = error.localizedDescription
            }
        }

        throw CloudflareR2UploaderError.publicURLValidationFailed(message: lastMessage)
    }

    private func validatePublicVideoURLOnce(_ url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        let (data, response) = try await networkManager.sendRawRequest(request)
        guard (200..<300).contains(response.statusCode) || response.statusCode == 206 else {
            throw CloudflareR2UploaderError.publicURLValidationFailed(
                message: "HTTP \(response.statusCode) for \(url.absoluteString): \(Self.previewString(from: data))"
            )
        }

        let contentType = response.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let isVideoLike = (contentType?.hasPrefix("video/") == true)
            || (contentType == "application/octet-stream")

        guard isVideoLike else {
            let ct = contentType ?? "(missing Content-Type)"
            throw CloudflareR2UploaderError.publicURLValidationFailed(
                message: "URL does not return a video MIME type (\(ct)) for \(url.absoluteString)."
            )
        }
    }

    private static func previewString(from data: Data) -> String {
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else {
            return "(empty response body)"
        }
        return String(text.prefix(400))
    }

    private static func amzDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func dayStamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

private enum R2Signing {
    static func canonicalURI(bucket: String, objectKey: String) -> String {
        var segments = [bucket]
        segments.append(contentsOf: objectKey.split(separator: "/").map(String.init))
        let encoded = segments.map(percentEncodePathSegment).joined(separator: "/")
        return "/\(encoded)"
    }

    static func percentEncodePathSegment(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) ?? segment
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hmacHex(key: Data, message: String) -> String {
        hmacData(key: key, message: message).map { String(format: "%02x", $0) }.joined()
    }

    static func signingKey(secretAccessKey: String, dateStamp: String, region: String, service: String) -> Data {
        let secret = Data(("AWS4" + secretAccessKey).utf8)
        let kDate = hmacData(key: secret, message: dateStamp)
        let kRegion = hmacData(key: kDate, message: region)
        let kService = hmacData(key: kRegion, message: service)
        return hmacData(key: kService, message: "aws4_request")
    }

    private static func hmacData(key: Data, message: String) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: symmetricKey)
        return Data(code)
    }

    private static let unreservedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
