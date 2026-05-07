import Foundation

enum CloudflareR2UploaderError: LocalizedError {
    case missingConfiguration(fields: [String])
    case invalidPublicBaseURL(String)
    case unsupportedVideoSource
    case unreadableLocalVideo(URL)
    case unsupportedFileSource
    case unreadableLocalFile(URL)
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
        case .unsupportedFileSource:
            return "Unsupported file input. Use a local file attachment."
        case .unreadableLocalFile(let url):
            return "Could not read local file: \(url.path)."
        case .malformedDataURL:
            return "Invalid data URL for attachment input."
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
    private enum PublicURLValidationKind {
        case video
        case pdf
    }

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
        return try await uploadPayload(
            payload,
            configuration: configuration,
            namespace: "jin-videos",
            validationKind: .video
        )
    }

    func uploadPDF(
        _ file: FileContent,
        configuration overrideConfiguration: CloudflareR2Configuration? = nil
    ) async throws -> URL {
        let configuration = try (overrideConfiguration ?? currentConfiguration()).validated()
        let payload = try localPDFPayload(from: file)
        return try await uploadPayload(
            payload,
            configuration: configuration,
            namespace: "jin-pdfs",
            validationKind: .pdf
        )
    }

    func deleteUploadedObject(
        at publicURL: URL,
        configuration overrideConfiguration: CloudflareR2Configuration? = nil
    ) async throws {
        let configuration = try (overrideConfiguration ?? currentConfiguration()).validated()
        let objectKey = try configuration.objectKey(for: publicURL)
        let request = try signedRequest(
            method: "DELETE",
            configuration: configuration,
            objectKey: objectKey,
            payloadData: Data(),
            contentType: nil
        )
        let (responseData, response) = try await networkManager.sendRawRequest(request)
        guard (200..<300).contains(response.statusCode) else {
            throw CloudflareR2UploaderError.uploadRejected(
                statusCode: response.statusCode,
                message: Self.previewString(from: responseData)
            )
        }
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

    private func uploadPayload(
        _ payload: CloudflareR2UploadPayload,
        configuration: CloudflareR2Configuration,
        namespace: String,
        validationKind: PublicURLValidationKind
    ) async throws -> URL {
        let objectKey = makeObjectKey(
            prefix: configuration.normalizedKeyPrefix,
            fileExtension: payload.fileExtension,
            namespace: namespace
        )

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
        try await validatePublicURL(publicURL, kind: validationKind)
        return publicURL
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
        try CloudflareR2SignedRequestFactory.makeRequest(
            method: method,
            configuration: configuration,
            objectKey: objectKey,
            payloadData: payloadData,
            contentType: contentType
        )
    }

    private func validatePublicURL(_ url: URL, kind: PublicURLValidationKind) async throws {
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
                try await validatePublicURLOnce(url, kind: kind)
                return
            } catch {
                lastMessage = error.localizedDescription
            }
        }

        throw CloudflareR2UploaderError.publicURLValidationFailed(message: lastMessage)
    }

    private func validatePublicURLOnce(_ url: URL, kind: PublicURLValidationKind) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        let (data, response) = try await networkManager.sendRawRequest(request)
        guard (200..<300).contains(response.statusCode) || response.statusCode == 206 else {
            throw CloudflareR2UploaderError.publicURLValidationFailed(
                message: "HTTP \(response.statusCode) for \(url.absoluteString): \(Self.previewString(from: data))"
            )
        }

        let contentType = response.value(forHTTPHeaderField: "Content-Type")
            .flatMap { $0.split(separator: ";").first.map(String.init)?.trimmedLowercased }

        let isExpectedContentType: Bool
        switch kind {
        case .video:
            isExpectedContentType = (contentType?.hasPrefix("video/") == true)
                || (contentType == "application/octet-stream")
        case .pdf:
            isExpectedContentType = (contentType == "application/pdf")
                || (contentType == "application/octet-stream")
        }

        guard isExpectedContentType else {
            let ct = contentType ?? "(missing Content-Type)"
            let expectedLabel = switch kind {
            case .video: "video"
            case .pdf: "PDF"
            }
            throw CloudflareR2UploaderError.publicURLValidationFailed(
                message: "URL does not return a \(expectedLabel) MIME type (\(ct)) for \(url.absoluteString)."
            )
        }
    }

    private static func previewString(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8)?.trimmedNonEmpty else {
            return "(empty response body)"
        }
        return String(text.prefix(400))
    }

    private static func dayStamp(from date: Date) -> String {
        CloudflareR2DateFormatter.dayStamp(from: date)
    }
}
