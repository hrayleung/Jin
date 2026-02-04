import Foundation

struct MCPMessageFramer {
    private var buffer = Data()
    private var preamble = Data()

    private let maxPreambleBytes: Int
    private let maxMessageBytes: Int

    init(maxPreambleBytes: Int = 64 * 1024, maxMessageBytes: Int = 10 * 1024 * 1024) {
        self.maxPreambleBytes = maxPreambleBytes
        self.maxMessageBytes = maxMessageBytes
    }

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    mutating func drainPreamble() -> Data? {
        guard !preamble.isEmpty else { return nil }
        let data = preamble
        preamble.removeAll(keepingCapacity: true)
        return data
    }

    mutating func nextMessage() throws -> Data? {
        // Some MCP servers accidentally write logs to stdout before framing begins.
        // Be resilient: drop any preamble before the first Content-Length header.
        let headerKey = [UInt8]("content-length".utf8)
        if let range = rangeOfASCIICaseInsensitive(headerKey, in: buffer), range.lowerBound > 0 {
            preamble.append(buffer.subdata(in: 0..<range.lowerBound))
            buffer.removeSubrange(0..<range.lowerBound)
        } else if buffer.count > maxPreambleBytes {
            let overflow = buffer.count - maxPreambleBytes
            preamble.append(buffer.subdata(in: 0..<overflow))
            buffer.removeSubrange(0..<overflow)
            return nil
        } else if rangeOfASCIICaseInsensitive(headerKey, in: buffer) == nil {
            return nil
        }

        let delimiterCRLF = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
        let delimiterLF = Data([0x0A, 0x0A]) // \n\n (tolerate non-CRLF framing)

        let headerRange: Range<Data.Index>?
        if let crlf = buffer.range(of: delimiterCRLF), let lf = buffer.range(of: delimiterLF) {
            headerRange = crlf.lowerBound < lf.lowerBound ? crlf : lf
        } else {
            headerRange = buffer.range(of: delimiterCRLF) ?? buffer.range(of: delimiterLF)
        }

        guard let headerRange else {
            return nil
        }

        let headerData = buffer.subdata(in: 0..<headerRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw MCPTransportError.invalidHeader
        }

        guard let contentLength = parseContentLength(from: headerString) else {
            throw MCPTransportError.missingContentLength
        }

        guard contentLength <= maxMessageBytes else {
            throw MCPTransportError.messageTooLarge(contentLength: contentLength, maxBytes: maxMessageBytes)
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
        for line in header.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else { continue }
            if parts[0].lowercased() == "content-length" {
                return Int(parts[1])
            }
        }
        return nil
    }

    private func rangeOfASCIICaseInsensitive(_ needle: [UInt8], in haystack: Data) -> Range<Data.Index>? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }

        func lower(_ byte: UInt8) -> UInt8 {
            if byte >= 65, byte <= 90 { return byte &+ 32 }
            return byte
        }

        let lastStart = haystack.count - needle.count
        for start in 0...lastStart {
            var matched = true
            for i in 0..<needle.count {
                if lower(haystack[start + i]) != needle[i] {
                    matched = false
                    break
                }
            }
            if matched {
                return start..<(start + needle.count)
            }
        }

        return nil
    }
}

enum MCPTransportError: Error, LocalizedError {
    case invalidHeader
    case missingContentLength
    case messageTooLarge(contentLength: Int, maxBytes: Int)

    var errorDescription: String? {
        switch self {
        case .invalidHeader:
            return "Invalid MCP message header."
        case .missingContentLength:
            return "Missing Content-Length header in MCP message."
        case .messageTooLarge(let contentLength, let maxBytes):
            return "MCP message too large (\(contentLength) bytes; max \(maxBytes))."
        }
    }
}
