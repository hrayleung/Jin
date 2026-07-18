import Foundation

/// Stream parser protocol.
protocol StreamParser: Sendable {
    associatedtype Event: Sendable

    /// Append a single byte (legacy entry point; prefer `append(_:Data)` for chunks).
    mutating func append(_ byte: UInt8)

    /// Append a network chunk. Default implementation walks bytes via `append(_:)`.
    /// High-throughput parsers should override this with range scans.
    mutating func append(_ data: Data)

    mutating func nextEvent() -> Event?

    /// Flush any buffered terminal event at EOF. Implementations must decide
    /// whether a delimiter-less tail is a complete event (emit) or incomplete (drop).
    mutating func finish()
}

extension StreamParser {
    mutating func append(_ data: Data) {
        for byte in data {
            append(byte)
        }
    }
}
