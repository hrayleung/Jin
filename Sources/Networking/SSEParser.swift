import Foundation

/// Server-Sent Events (SSE) parser for OpenAI and xAI
struct SSEParser: StreamParser {
    private var buffer = Data()
    private var events: [SSEEvent] = []

    mutating func append(_ byte: UInt8) {
        buffer.append(byte)

        // Check for double newline (event boundary)
        if buffer.count >= 2 {
            let lastTwo = buffer.suffix(2)
            if lastTwo == Data([0x0A, 0x0A]) { // \n\n
                parseEvent()
                return
            }
        }

        // Also support CRLF boundaries (\r\n\r\n)
        if buffer.count >= 4 {
            let lastFour = buffer.suffix(4)
            if lastFour == Data([0x0D, 0x0A, 0x0D, 0x0A]) { // \r\n\r\n
                parseEvent()
            }
        }
    }

    mutating func nextEvent() -> SSEEvent? {
        events.isEmpty ? nil : events.removeFirst()
    }

    private mutating func parseEvent() {
        defer { buffer.removeAll() }

        guard let eventString = String(data: buffer, encoding: .utf8) else {
            return
        }

        var eventType: String?
        var eventData: String?

        for line in eventString.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            if trimmed.hasPrefix("event:") {
                eventType = String(trimmed.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines))
            } else if trimmed.hasPrefix("data:") {
                let dataString = String(trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines))
                guard !dataString.isEmpty else {
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

/// SSE event
enum SSEEvent: Sendable {
    case event(type: String, data: String)
    case done
}

/// JSON Lines parser for Anthropic and Vertex AI
struct JSONLineParser: StreamParser {
    private var buffer = Data()
    private var events: [String] = []

    mutating func append(_ byte: UInt8) {
        buffer.append(byte)

        // Check for newline (line boundary)
        if byte == 0x0A { // \n
            parseLine()
        }
    }

    mutating func nextEvent() -> String? {
        events.isEmpty ? nil : events.removeFirst()
    }

    private mutating func parseLine() {
        defer { buffer.removeAll() }

        guard !buffer.isEmpty,
              let lineString = String(data: buffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lineString.isEmpty else {
            return
        }

        events.append(lineString)
    }
}
