import Darwin
import Foundation

/// Short-lived HTTP listener that captures a single OAuth redirect on 127.0.0.1.
final class MCPOAuthLoopbackServer: @unchecked Sendable {
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var redirectURI: URL?
    private var acceptTask: Task<Void, Never>?

    func start(redirectURI: URL) async throws {
        guard let portNumber = redirectURI.port, (1...65_535).contains(portNumber) else {
            throw MCPOAuthError.browserUnavailable
        }

        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw MCPOAuthError.browserUnavailable }

        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(portNumber)).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw MCPOAuthError.browserUnavailable
        }
        guard listen(fd, 8) == 0 else {
            close(fd)
            throw MCPOAuthError.browserUnavailable
        }

        lock.withLock {
            self.listenFD = fd
            self.redirectURI = redirectURI
        }
    }

    func accept(timeoutSeconds: TimeInterval) async throws -> URL {
        let fd = lock.withLock { listenFD }
        let redirectURI = lock.withLock { self.redirectURI }
        guard fd >= 0, let redirectURI else { throw MCPOAuthError.browserUnavailable }

        return try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask {
                try await self.acceptMatchingCallback(listenFD: fd, redirectURI: redirectURI)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                self.stop()
                throw MCPOAuthError.authorizationFailed("Sign-in timed out. Try again.")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func stop() {
        let fd = lock.withLock { () -> Int32 in
            let current = listenFD
            listenFD = -1
            return current
        }
        if fd >= 0 {
            Darwin.close(fd)
        }
    }

    private func acceptMatchingCallback(listenFD: Int32, redirectURI: URL) async throws -> URL {
        while !Task.isCancelled {
            let clientFD = try await acceptClient(listenFD: listenFD)
            defer { Darwin.close(clientFD) }
            if let url = try handle(clientFD: clientFD, redirectURI: redirectURI) {
                return url
            }
        }
        throw MCPOAuthError.cancelled
    }

    private func acceptClient(listenFD: Int32) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var address = sockaddr_in()
                var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientFD = withUnsafeMutablePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                        Darwin.accept(listenFD, sockaddrPointer, &length)
                    }
                }
                if clientFD >= 0 {
                    continuation.resume(returning: clientFD)
                } else {
                    continuation.resume(throwing: MCPOAuthError.cancelled)
                }
            }
        }
    }

    private func handle(clientFD: Int32, redirectURI: URL) throws -> URL? {
        let request = try readHTTPRequest(from: clientFD)
        guard let callback = MCPOAuthLoopbackListener.callbackURL(
            fromHTTPRequest: request,
            redirectURI: redirectURI
        ) else {
            _ = writeHTTP(response(status: 404, html: Self.notFoundHTML), to: clientFD)
            return nil
        }

        let html = MCPOAuthLoopbackListener.errorMessage(fromCallback: callback) == nil
            ? Self.successHTML
            : Self.deniedHTML
        _ = writeHTTP(response(status: 200, html: html), to: clientFD)
        return callback
    }

    private func readHTTPRequest(from fd: Int32) throws -> String {
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while collected.count < 65_536 {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            collected.append(contentsOf: buffer.prefix(count))
            if let text = String(data: collected, encoding: .utf8),
               text.contains("\r\n\r\n") || text.contains("\n\n") {
                return text
            }
        }
        guard let text = String(data: collected, encoding: .utf8), !text.isEmpty else {
            throw MCPOAuthError.invalidCallback
        }
        return text
    }

    @discardableResult
    private func writeHTTP(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return false }
            var written = 0
            while written < data.count {
                let count = Darwin.write(fd, base.advanced(by: written), data.count - written)
                if count <= 0 { return false }
                written += count
            }
            return true
        }
    }

    private func response(status: Int, html: String) -> Data {
        let body = Data(html.utf8)
        let reason = status == 200 ? "OK" : "Not Found"
        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        var data = Data(header.utf8)
        data.append(body)
        return data
    }

    private static let successHTML = """
    <!doctype html>
    <html>
    <head><meta charset="utf-8"><title>Jin</title></head>
    <body style="font:16px/1.5 -apple-system,BlinkMacSystemFont,sans-serif;padding:48px;text-align:center;color:#1d1d1f">
    <h1 style="font-size:22px;font-weight:600">Signed in</h1>
    <p>You can close this window and return to Jin.</p>
    </body>
    </html>
    """

    private static let deniedHTML = """
    <!doctype html>
    <html>
    <head><meta charset="utf-8"><title>Jin</title></head>
    <body style="font:16px/1.5 -apple-system,BlinkMacSystemFont,sans-serif;padding:48px;text-align:center;color:#1d1d1f">
    <h1 style="font-size:22px;font-weight:600">Sign-in didn’t finish</h1>
    <p>You can close this window and try again in Jin.</p>
    </body>
    </html>
    """

    private static let notFoundHTML = """
    <!doctype html>
    <html><body>Not found</body></html>
    """
}
