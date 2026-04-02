import Foundation
import Alamofire

actor MinerUOCRClient {
    enum Constants {
        static let defaultBaseURL = URL(string: "https://mineru.net")!
        static let defaultLanguage = "ch"
        static let defaultModelVersion = "vlm"
        static let defaultPollIntervalNanoseconds: UInt64 = 3_000_000_000
    }

    private let apiToken: String
    private let userToken: String?
    private let baseURL: URL
    private let networkManager: NetworkManager

    init(
        apiToken: String,
        userToken: String? = nil,
        baseURL: URL = Constants.defaultBaseURL,
        networkManager: NetworkManager = NetworkManager()
    ) {
        self.apiToken = apiToken
        self.userToken = userToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL
        self.networkManager = networkManager
    }

    func validateAPIKey(
        language: String = Constants.defaultLanguage,
        timeoutSeconds: TimeInterval = 30
    ) async throws {
        _ = try await createBatchUpload(
            filename: "validation.pdf",
            language: language,
            timeoutSeconds: timeoutSeconds
        )
    }

    func ocrPDF(
        _ pdfData: Data,
        filename: String,
        language: String = Constants.defaultLanguage,
        timeoutSeconds: TimeInterval = 180,
        pollIntervalNanoseconds: UInt64 = Constants.defaultPollIntervalNanoseconds
    ) async throws -> String {
        let bootstrap = try await createBatchUpload(
            filename: filename,
            language: language,
            timeoutSeconds: timeoutSeconds
        )
        guard let uploadURL = bootstrap.uploadURLs.first else {
            throw LLMError.decodingError(message: "MinerU did not return an upload URL.")
        }

        try await uploadPDF(pdfData, to: uploadURL, timeoutSeconds: timeoutSeconds)

        let fullZipURL = try await pollForFullZipURL(
            batchID: bootstrap.batchID,
            timeoutSeconds: timeoutSeconds,
            pollIntervalNanoseconds: pollIntervalNanoseconds
        )
        return try await downloadAndExtractMarkdown(from: fullZipURL, timeoutSeconds: timeoutSeconds)
    }

    private func createBatchUpload(
        filename: String,
        language: String,
        timeoutSeconds: TimeInterval
    ) async throws -> UploadBootstrap {
        let body = BatchUploadRequest(
            enableFormula: true,
            enableTable: true,
            language: normalizedLanguage(language),
            files: [
                BatchUploadRequest.FileDescriptor(
                    name: filename,
                    isOCR: true,
                    dataID: UUID().uuidString.lowercased()
                )
            ],
            modelVersion: Constants.defaultModelVersion
        )

        let request = try NetworkRequestFactory.makeJSONRequest(
            url: endpoint("api/v4/file-urls/batch"),
            timeoutSeconds: timeoutSeconds,
            headers: requestHeaders(),
            body: body
        )
        let (data, _) = try await networkManager.sendRequest(request)
        let response: APIEnvelope<BatchUploadResponse> = try decodeEnvelope(from: data)

        guard let payload = response.data else {
            throw LLMError.decodingError(message: "MinerU file-urls response was missing data.")
        }
        guard !payload.batchID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.decodingError(message: "MinerU file-urls response was missing batch_id.")
        }

        return UploadBootstrap(
            batchID: payload.batchID,
            uploadURLs: payload.fileURLs.compactMap(URL.init(string:))
        )
    }

    private func uploadPDF(
        _ pdfData: Data,
        to uploadURL: URL,
        timeoutSeconds: TimeInterval
    ) async throws {
        let request = NetworkRequestFactory.makeRequest(
            url: uploadURL,
            method: .put,
            timeoutSeconds: timeoutSeconds,
            body: pdfData
        )
        let (_, response) = try await networkManager.sendRawRequest(request)
        guard (200 ..< 300).contains(response.statusCode) else {
            throw LLMError.invalidRequest(message: "MinerU upload failed with HTTP \(response.statusCode).")
        }
    }

    private func pollForFullZipURL(
        batchID: String,
        timeoutSeconds: TimeInterval,
        pollIntervalNanoseconds: UInt64
    ) async throws -> URL {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastState = "pending"
        var lastErrorMessage: String?

        while Date() < deadline {
            let request = NetworkRequestFactory.makeRequest(
                url: endpoint("api/v4/extract-results/batch/\(batchID)"),
                method: .get,
                timeoutSeconds: min(timeoutSeconds, 30),
                headers: requestHeaders()
            )
            let (data, _) = try await networkManager.sendRequest(request)
            let response: APIEnvelope<BatchResultResponse> = try decodeEnvelope(from: data)
            let result = response.data?.extractResult.first

            if let result {
                let state = result.state.lowercased()
                lastState = state
                lastErrorMessage = result.errorMessage

                if state == "done" || state == "success" || state == "completed" {
                    guard let raw = result.fullZipURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !raw.isEmpty,
                          let url = URL(string: raw) else {
                        throw LLMError.decodingError(message: "MinerU completed without returning a valid full_zip_url.")
                    }
                    return url
                }

                if state == "failed" || state == "error" {
                    let reason = (result.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                        ?? "Unknown extraction failure."
                    throw LLMError.invalidRequest(message: "MinerU extraction failed: \(reason)")
                }
            }

            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        let reasonSuffix: String
        if let lastErrorMessage, !lastErrorMessage.isEmpty {
            reasonSuffix = " Last error: \(lastErrorMessage)"
        } else {
            reasonSuffix = ""
        }
        throw LLMError.invalidRequest(message: "MinerU extraction timed out while waiting for completion. Last state: \(lastState).\(reasonSuffix)")
    }

    private func downloadAndExtractMarkdown(
        from archiveURL: URL,
        timeoutSeconds: TimeInterval
    ) async throws -> String {
        let request = NetworkRequestFactory.makeRequest(
            url: archiveURL,
            timeoutSeconds: timeoutSeconds
        )
        let (data, _) = try await networkManager.sendRequest(request)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JinMinerU-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let archiveFileURL = tempDirectory.appendingPathComponent("result.zip", isDirectory: false)
        try data.write(to: archiveFileURL, options: .atomic)

        guard let markdownEntryPath = archiveEntryPath(named: "full.md", in: archiveFileURL) else {
            throw LLMError.invalidRequest(message: "MinerU result archive did not contain a readable full.md file.")
        }

        guard let markdownData = runProcessData(
            executablePath: "/usr/bin/unzip",
            arguments: ["-p", archiveFileURL.path, markdownEntryPath]
        ),
        let markdown = String(data: markdownData, encoding: .utf8) else {
            throw LLMError.invalidRequest(message: "MinerU result archive did not contain a readable full.md file.")
        }

        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LLMError.invalidRequest(message: "MinerU returned an empty full.md file.")
        }
        return trimmed
    }

    private func requestHeaders() -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.update(name: "Authorization", value: "Bearer \(apiToken)")
        if let userToken, !userToken.isEmpty {
            headers.update(name: "token", value: userToken)
        }
        return headers
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func normalizedLanguage(_ language: String) -> String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Constants.defaultLanguage : trimmed
    }

    private func decodeEnvelope<T: Decodable>(from data: Data) throws -> APIEnvelope<T> {
        do {
            let decoder = JSONDecoder()
            let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
            if envelope.code != 0 {
                let message = envelope.message?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw LLMError.providerError(
                    code: "mineru_\(envelope.code)",
                    message: message?.isEmpty == false ? message! : "MinerU returned code \(envelope.code)."
                )
            }
            return envelope
        } catch let error as LLMError {
            throw error
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }

    private func runProcessData(executablePath: String, arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }
        return stdout.fileHandleForReading.readDataToEndOfFile()
    }

    private func archiveEntryPath(named filename: String, in archiveFileURL: URL) -> String? {
        guard let data = runProcessData(
            executablePath: "/usr/bin/unzip",
            arguments: ["-Z1", archiveFileURL.path]
        ),
        let listing = String(data: data, encoding: .utf8) else {
            return nil
        }

        let entries = listing
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        if let exactMatch = entries.first(where: { $0 == filename }) {
            return exactMatch
        }
        return entries.first(where: { $0.hasSuffix("/\(filename)") })
    }
}

private struct UploadBootstrap {
    let batchID: String
    let uploadURLs: [URL]
}

private struct APIEnvelope<T: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: T?

    enum CodingKeys: String, CodingKey {
        case code
        case message = "msg"
        case data
    }
}

private struct BatchUploadRequest: Encodable {
    struct FileDescriptor: Encodable {
        let name: String
        let isOCR: Bool
        let dataID: String

        enum CodingKeys: String, CodingKey {
            case name
            case isOCR = "is_ocr"
            case dataID = "data_id"
        }
    }

    let enableFormula: Bool
    let enableTable: Bool
    let language: String
    let files: [FileDescriptor]
    let modelVersion: String

    enum CodingKeys: String, CodingKey {
        case enableFormula = "enable_formula"
        case enableTable = "enable_table"
        case language
        case files
        case modelVersion = "model_version"
    }
}

private struct BatchUploadResponse: Decodable {
    let batchID: String
    let fileURLs: [String]

    enum CodingKeys: String, CodingKey {
        case batchID = "batch_id"
        case fileURLs = "file_urls"
    }
}

private struct BatchResultResponse: Decodable {
    let extractResult: [ResultItem]

    struct ResultItem: Decodable {
        let state: String
        let fullZipURL: String?
        let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case state
            case fullZipURL = "full_zip_url"
            case errorMessage = "err_msg"
        }
    }

    enum CodingKeys: String, CodingKey {
        case extractResult = "extract_result"
    }
}
