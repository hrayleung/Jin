import Collections
import Foundation

/// Server-Sent Events (SSE) parser for OpenAI and xAI.
///
/// Accepts whole network chunks and scans for `\n\n` / `\r\n\r\n` boundaries
/// instead of feeding one byte at a time (avoids per-byte `Data.append` + suffix checks).
struct SSEParser: StreamParser {
    private var buffer = Data()
    private var events: Deque<SSEEvent> = []

    mutating func append(_ byte: UInt8) {
        append(Data([byte]))
    }

    mutating func append(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        extractCompleteEvents()
    }

    mutating func nextEvent() -> SSEEvent? {
        events.popFirst()
    }

    mutating func finish() {
        guard !buffer.isEmpty else { return }
        parseEvent(from: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    private mutating func extractCompleteEvents() {
        // Scan buffer for event boundaries without allocating per-byte suffixes.
        var searchStart = 0
        while searchStart < buffer.count {
            guard let boundary = nextSSEBoundary(in: buffer, from: searchStart) else {
                // Keep only the unparsed tail.
                if searchStart > 0 {
                    buffer.removeSubrange(0..<searchStart)
                }
                return
            }

            let eventData = buffer.subdata(in: searchStart..<boundary.start)
            parseEvent(from: eventData)
            searchStart = boundary.end
        }
        buffer.removeAll(keepingCapacity: true)
    }

    private mutating func parseEvent(from eventBytes: Data) {
        guard !eventBytes.isEmpty,
              let eventString = String(data: eventBytes, encoding: .utf8) else {
            return
        }

        var eventType: String?
        var eventData: String?

        for line in eventString.components(separatedBy: .newlines) {
            guard let trimmed = line.trimmedNonEmpty else {
                continue
            }

            if trimmed.hasPrefix("event:") {
                eventType = String(trimmed.dropFirst(6)).trimmed
            } else if trimmed.hasPrefix("data:") {
                guard let dataString = String(trimmed.dropFirst(5)).trimmedNonEmpty else {
                    continue
                }
                if dataString == "[DONE]" {
                    events.append(.done)
                    return
                }
                eventData = dataString
            }
        }

        if let eventData {
            events.append(.event(type: eventType ?? "message", data: eventData))
        }
    }
}

/// Byte range of an SSE event boundary separator within a buffer.
private struct SSEBoundary {
    let start: Int
    let end: Int
}

/// Finds the next `\n\n` or `\r\n\r\n` boundary at or after `from`.
private func nextSSEBoundary(in data: Data, from: Int) -> SSEBoundary? {
    guard from < data.count else { return nil }

    return data.withUnsafeBytes { rawBuffer -> SSEBoundary? in
        guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
            return nil
        }
        let count = rawBuffer.count
        var i = from
        while i < count {
            let byte = base[i]
            if byte == 0x0A { // \n
                let next = i + 1
                if next < count, base[next] == 0x0A {
                    return SSEBoundary(start: i, end: next + 1)
                }
            } else if byte == 0x0D { // \r
                // \r\n\r\n
                if i + 3 < count,
                   base[i + 1] == 0x0A,
                   base[i + 2] == 0x0D,
                   base[i + 3] == 0x0A {
                    return SSEBoundary(start: i, end: i + 4)
                }
            }
            i += 1
        }
        return nil
    }
}

/// SSE event
enum SSEEvent: Sendable {
    case event(type: String, data: String)
    case done
}

/// JSON Lines parser for Anthropic and Vertex AI.
struct JSONLineParser: StreamParser {
    private var buffer = Data()
    private var events: Deque<String> = []

    mutating func append(_ byte: UInt8) {
        append(Data([byte]))
    }

    mutating func append(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        extractCompleteLines()
    }

    mutating func nextEvent() -> String? {
        events.popFirst()
    }

    mutating func finish() {
        guard !buffer.isEmpty else { return }
        parseLine(from: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    private mutating func extractCompleteLines() {
        var searchStart = 0
        while searchStart < buffer.count {
            guard let newlineIndex = buffer[searchStart...].firstIndex(of: 0x0A) else {
                if searchStart > 0 {
                    buffer.removeSubrange(0..<searchStart)
                }
                return
            }
            let lineData = buffer.subdata(in: searchStart..<newlineIndex)
            parseLine(from: lineData)
            searchStart = newlineIndex + 1
        }
        buffer.removeAll(keepingCapacity: true)
    }

    private mutating func parseLine(from lineBytes: Data) {
        guard !lineBytes.isEmpty,
              let lineString = String(data: lineBytes, encoding: .utf8)?.trimmedNonEmpty else {
            return
        }
        events.append(lineString)
    }
}
