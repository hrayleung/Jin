import Foundation

/// A `Codable` type whose wire format is a single bare string, round-tripped through
/// `rawValue` / `init(rawValue:)`. Used by the open status enums (which carry an
/// `.unknown(String)` fallback for forward compatibility) so they share one
/// single-value-container Codable implementation.
///
/// Conformers must NOT also declare an explicit `init(from:)` / `encode(to:)`, and the
/// `.unknown(String)` payload means the compiler cannot auto-synthesize Codable here —
/// so the default implementations below are what's used. `StatusEnumWireFormatTests`
/// pins the resulting wire format.
protocol RawStringCodable: Codable {
    init(rawValue: String)
    var rawValue: String { get }
}

extension RawStringCodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
