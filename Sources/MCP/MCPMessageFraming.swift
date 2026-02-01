import Foundation

struct MCPMessageFramer {
    private var buffer = Data()

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    mutating func nextMessage() throws -> Data? {
        let delimiter = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
        guard let headerRange = buffer.range(of: delimiter) else {
            return nil
        }

        let headerData = buffer.subdata(in: 0..<headerRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw MCPTransportError.invalidHeader
        }

        guard let contentLength = parseContentLength(from: headerString) else {
            throw MCPTransportError.missingContentLength
        }

        let bodyStart = headerRange.upperBound
        let bodyEnd = bodyStart + contentLength

        guard buffer.count >= bodyEnd else {
            return nil
        }

        let messageData = buffer.subdata(in: bodyStart..<bodyEnd)
        buffer.removeSubrange(0..<bodyEnd)
        return messageData
    }

    static func frame(_ message: Data) -> Data {
        var framed = Data()
        framed.append("Content-Length: \(message.count)\r\n\r\n".data(using: .utf8)!)
        framed.append(message)
        return framed
    }

    private func parseContentLength(from header: String) -> Int? {
        for line in header.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0].lowercased() == "content-length" {
                return Int(parts[1])
            }
        }
        return nil
    }
}

enum MCPTransportError: Error, LocalizedError {
    case invalidHeader
    case missingContentLength

    var errorDescription: String? {
        switch self {
        case .invalidHeader:
            return "Invalid MCP message header."
        case .missingContentLength:
            return "Missing Content-Length header in MCP message."
        }
    }
}

