import Foundation

actor NetworkDebugLogger {
    static let shared = NetworkDebugLogger()

    /// Kept for compatibility with existing call sites.
    static let maxBodyBytes = Int.max

    private struct ActiveRequest {
        let mode: String
        let context: NetworkDebugLogContext
        let startedAt: Date
        let requestRecord: [String: Any]
        let fileURL: URL
    }

    private struct ActiveWebSocketSession {
        let context: NetworkDebugLogContext
        let startedAt: Date
        let url: String
        let requestHeaders: [String: String]
        var frames: [[String: Any]]
        let fileURL: URL
    }

    private let isoFormatter = ISO8601DateFormatter()
    private var activeRequests: [UUID: ActiveRequest] = [:]
    private var activeWebSocketSessions: [UUID: ActiveWebSocketSession] = [:]

    nonisolated static var logRootDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Jin", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("network-trace", isDirectory: true)
    }

    static var isLoggingEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKeys.networkDebugLoggingEnabled)
    }

    private init() {
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func beginRequest(_ request: URLRequest, mode: String) async -> UUID? {
        guard Self.isLoggingEnabled else { return nil }

        let context = NetworkDebugLogScope.current ?? NetworkDebugLogContext()
        guard context.conversationID != nil else { return nil }

        let requestID = UUID()
        let startedAt = Date()
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "<nil>"
        let headers = headers(from: request.allHTTPHeaderFields)
        let body = bodyValue(
            data: request.httpBody,
            contentType: request.value(forHTTPHeaderField: "Content-Type")
        )

        var requestRecord: [String: Any] = [
            "ts": timestamp(),
            "method": method,
            "url": url,
            "headers": headers
        ]
        if let body {
            requestRecord["body"] = body
        }

        activeRequests[requestID] = ActiveRequest(
            mode: mode,
            context: context,
            startedAt: startedAt,
            requestRecord: requestRecord,
            fileURL: Self.logFileURL(for: context, startedAt: startedAt, requestID: requestID)
        )
        return requestID
    }

    func endRequest(
        requestID: UUID?,
        response: HTTPURLResponse?,
        responseBody: Data?,
        responseBodyTruncated: Bool,
        error: Error?
    ) async {
        guard Self.isLoggingEnabled else { return }
        guard let requestID else { return }

        let metadata = activeRequests.removeValue(forKey: requestID)
            ?? ActiveRequest(
                mode: "unknown",
                context: NetworkDebugLogScope.current ?? NetworkDebugLogContext(),
                startedAt: Date(),
                requestRecord: ["ts": timestamp()],
                fileURL: Self.logFileURL(
                    for: NetworkDebugLogScope.current ?? NetworkDebugLogContext(),
                    startedAt: Date(),
                    requestID: requestID
                )
            )

        let responseHeaders = response.map { headers(from: stringifyHeaders($0.allHeaderFields)) } ?? [:]
        let body = bodyValue(
            data: responseBody,
            contentType: response?.value(forHTTPHeaderField: "Content-Type")
        )

        var responseRecord: [String: Any] = [
            "ts": timestamp(),
            "status": response?.statusCode ?? NSNull(),
            "headers": responseHeaders,
            "latency_ms": Int(Date().timeIntervalSince(metadata.startedAt) * 1000),
            "body_truncated": responseBodyTruncated
        ]
        if let responseURL = response?.url?.absoluteString {
            responseRecord["url"] = responseURL
        }
        if let body {
            responseRecord["body"] = body
        }
        if let providerRequestID = providerRequestID(from: responseHeaders) {
            responseRecord["provider_request_id"] = providerRequestID
        }
        responseRecord["error"] = error?.localizedDescription ?? NSNull()

        let record: [String: Any] = [
            "request_id": requestID.uuidString,
            "mode": metadata.mode,
            "context": metadata.context.jsonObject,
            "request": metadata.requestRecord,
            "response": responseRecord
        ]

        await writeRecord(record, to: metadata.fileURL)
    }

    // MARK: - WebSocket Session Logging

    func beginWebSocketSession(url: URL, headers: [String: String]?) async -> UUID? {
        guard Self.isLoggingEnabled else { return nil }

        let context = NetworkDebugLogScope.current ?? NetworkDebugLogContext()
        guard context.conversationID != nil else { return nil }

        let sessionID = UUID()
        let startedAt = Date()

        activeWebSocketSessions[sessionID] = ActiveWebSocketSession(
            context: context,
            startedAt: startedAt,
            url: url.absoluteString,
            requestHeaders: headers ?? [:],
            frames: [],
            fileURL: Self.logFileURL(for: context, startedAt: startedAt, requestID: sessionID)
        )
        return sessionID
    }

    func logWebSocketSend(sessionID: UUID?, message: String) async {
        guard Self.isLoggingEnabled, let sessionID,
              var session = activeWebSocketSessions[sessionID] else { return }

        var frame: [String: Any] = [
            "ts": timestamp(),
            "direction": "send"
        ]

        if let data = message.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            frame["body"] = json
        } else {
            frame["body"] = message
        }

        session.frames.append(frame)
        activeWebSocketSessions[sessionID] = session
    }

    func logWebSocketReceive(sessionID: UUID?, message: String) async {
        guard Self.isLoggingEnabled, let sessionID,
              var session = activeWebSocketSessions[sessionID] else { return }

        var frame: [String: Any] = [
            "ts": timestamp(),
            "direction": "receive"
        ]

        if let data = message.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            frame["body"] = json
        } else {
            frame["body"] = message
        }

        session.frames.append(frame)
        activeWebSocketSessions[sessionID] = session
    }

    func endWebSocketSession(sessionID: UUID?, error: Error?) async {
        guard Self.isLoggingEnabled, let sessionID else { return }

        guard let session = activeWebSocketSessions.removeValue(forKey: sessionID) else { return }

        let record: [String: Any] = [
            "request_id": sessionID.uuidString,
            "mode": "websocket",
            "context": session.context.jsonObject,
            "connection": [
                "ts": isoFormatter.string(from: session.startedAt),
                "url": session.url,
                "headers": session.requestHeaders
            ],
            "frames": session.frames,
            "closed": [
                "ts": timestamp(),
                "latency_ms": Int(Date().timeIntervalSince(session.startedAt) * 1000),
                "error": error?.localizedDescription ?? NSNull()
            ] as [String: Any]
        ]

        await writeRecord(record, to: session.fileURL)
    }

    func clearLogFile() async throws {
        try await clearLogs()
    }

    func clearLogs() async throws {
        let root = Self.logRootDirectoryURL
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        activeRequests.removeAll()
        activeWebSocketSessions.removeAll()
    }

    private func timestamp() -> String {
        isoFormatter.string(from: Date())
    }

    private func writeRecord(_ record: [String: Any], to fileURL: URL) async {
        guard JSONSerialization.isValidJSONObject(record) else { return }
        guard let payload = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) else { return }

        let parent = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try payload.write(to: fileURL, options: [.atomic])
        } catch {
            // Keep logging failure silent to avoid affecting normal request flow.
        }
    }

    private func headers(from headers: [String: String]?) -> [String: String] {
        guard let headers else { return [:] }
        return headers
    }

    private func stringifyHeaders(_ headers: [AnyHashable: Any]) -> [String: String] {
        var out: [String: String] = [:]
        out.reserveCapacity(headers.count)
        for (rawKey, rawValue) in headers {
            guard let key = rawKey as? String else { continue }
            out[key] = String(describing: rawValue)
        }
        return out
    }

    private func bodyValue(data: Data?, contentType: String?) -> Any? {
        guard let data, !data.isEmpty else { return nil }

        let loweredContentType = (contentType ?? "").lowercased()
        if loweredContentType.contains("application/json"),
           let object = try? JSONSerialization.jsonObject(with: data) {
            return object
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        return "<\(data.count) bytes (binary/base64): \(data.base64EncodedString())>"
    }

    private func providerRequestID(from headers: [String: String]) -> String? {
        let candidates = [
            "request-id",
            "x-request-id",
            "anthropic-request-id",
            "openai-request-id",
            "x-amzn-requestid"
        ]
        for candidate in candidates {
            if let match = headers.first(where: { $0.key.caseInsensitiveCompare(candidate) == .orderedSame })?.value,
               !match.isEmpty {
                return match
            }
        }
        return nil
    }

    private nonisolated static func logFileURL(
        for context: NetworkDebugLogContext,
        startedAt: Date,
        requestID: UUID
    ) -> URL {
        let timeFolder = safePathComponent(timeFolderComponent(for: startedAt))
        let conversation = safePathComponent(context.conversationID ?? "_unscoped_conversation")
        let turn = safePathComponent(context.turnID ?? "_unscoped_turn")
        return logRootDirectoryURL
            .appendingPathComponent(timeFolder, isDirectory: true)
            .appendingPathComponent(conversation, isDirectory: true)
            .appendingPathComponent(turn, isDirectory: true)
            .appendingPathComponent("\(requestID.uuidString).json", isDirectory: false)
    }

    private nonisolated static func timeFolderComponent(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: date)
    }

    private nonisolated static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let normalized = String(scalars)
        return normalized.isEmpty ? "_empty" : normalized
    }
}
