import CryptoKit
import Foundation

enum SHA256HexDigest {
    static func string(_ value: String) -> String {
        data(Data(value.utf8))
    }

    static func data(_ value: Data) -> String {
        SHA256.hash(data: value)
            .map(hexByte)
            .joined()
    }

    static func dataPrefix(_ value: Data, byteCount: Int) -> String {
        SHA256.hash(data: value)
            .prefix(max(0, byteCount))
            .map(hexByte)
            .joined()
    }

    private static func hexByte(_ byte: UInt8) -> String {
        String(format: "%02x", byte)
    }
}
