/// Stream parser protocol.
protocol StreamParser: Sendable {
    associatedtype Event: Sendable

    mutating func append(_ byte: UInt8)
    mutating func nextEvent() -> Event?
    mutating func finish()
}

extension StreamParser {
    mutating func finish() {}
}
