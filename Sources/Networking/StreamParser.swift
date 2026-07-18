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
    mutating func finish()
}

extension StreamParser {
    mutating func append(_ data: Data) {
        for byte in data {
            append(byte)
        }
    }

    mutating func finish() {}
}
