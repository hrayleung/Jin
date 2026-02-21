import Foundation
import CryptoKit

// MARK: - JWT Types

struct JWTHeader: Codable {
    let alg: String
    let typ: String
}

struct JWTClaims: Codable {
    let iss: String
    let scope: String
    let aud: String
    let iat: Int
    let exp: Int
}

struct TokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - Base64URL Encoding

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - PEM Parsing

struct PEMBlock {
    let label: String
    let derBytes: Data

    static func parse(pem: String) throws -> PEMBlock {
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LLMError.invalidRequest(message: "Empty private key")
        }

        let lines = trimmed
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let beginIndex = lines.firstIndex(where: { $0.hasPrefix("-----BEGIN ") }) else {
            guard let der = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters) else {
                throw LLMError.invalidRequest(message: "Invalid private key format (expected PEM)")
            }
            return PEMBlock(label: "UNKNOWN", derBytes: der)
        }

        guard let endIndex = lines[(beginIndex + 1)...].firstIndex(where: { $0.hasPrefix("-----END ") }) else {
            throw LLMError.invalidRequest(message: "Invalid private key format (missing PEM end marker)")
        }

        let beginLine = lines[beginIndex]
        let endLine = lines[endIndex]

        guard let beginLabel = parseLabel(line: beginLine, prefix: "-----BEGIN ") else {
            throw LLMError.invalidRequest(message: "Invalid PEM begin marker")
        }
        guard let endLabel = parseLabel(line: endLine, prefix: "-----END ") else {
            throw LLMError.invalidRequest(message: "Invalid PEM end marker")
        }
        guard beginLabel == endLabel else {
            throw LLMError.invalidRequest(message: "Mismatched PEM markers (\(beginLabel) vs \(endLabel))")
        }

        let base64Content = lines[(beginIndex + 1)..<endIndex].joined()
        guard let der = Data(base64Encoded: base64Content, options: .ignoreUnknownCharacters) else {
            throw LLMError.invalidRequest(message: "Invalid PEM base64 content")
        }

        return PEMBlock(label: beginLabel, derBytes: der)
    }

    private static func parseLabel(line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix), line.hasSuffix("-----") else { return nil }
        let start = line.index(line.startIndex, offsetBy: prefix.count)
        let end = line.index(line.endIndex, offsetBy: -5)
        return String(line[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - PKCS8

enum PKCS8 {
    private static let rsaAlgorithmOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]

    static func extractPKCS1RSAPrivateKey(from pkcs8DER: Data) throws -> Data {
        var reader = DERReader(data: pkcs8DER)
        let outer = try reader.readTLV(expectedTag: 0x30)

        var seq = DERReader(data: outer.value)
        _ = try seq.readTLV(expectedTag: 0x02) // version

        let algorithmIdentifier = try seq.readTLV(expectedTag: 0x30)
        var algReader = DERReader(data: algorithmIdentifier.value)
        let oid = try algReader.readTLV(expectedTag: 0x06)
        guard Array(oid.value) == rsaAlgorithmOID else {
            throw LLMError.invalidRequest(message: "Unsupported private key algorithm (expected RSA)")
        }

        _ = try? algReader.readTLV(expectedTag: 0x05)

        let privateKey = try seq.readTLV(expectedTag: 0x04)
        return privateKey.value
    }
}

// MARK: - RSA Key Parsing

enum RSAKeyParsing {
    static func modulusSizeInBits(fromPKCS1RSAPrivateKey pkcs1DER: Data) throws -> Int {
        var reader = DERReader(data: pkcs1DER)
        let outer = try reader.readTLV(expectedTag: 0x30)

        var seq = DERReader(data: outer.value)
        _ = try seq.readTLV(expectedTag: 0x02) // version
        let modulus = try seq.readTLV(expectedTag: 0x02)

        var modulusBytes = [UInt8](modulus.value)
        while modulusBytes.first == 0, modulusBytes.count > 1 {
            modulusBytes.removeFirst()
        }
        guard !modulusBytes.isEmpty else {
            throw LLMError.invalidRequest(message: "Invalid RSA private key (missing modulus)")
        }

        return modulusBytes.count * 8
    }
}

// MARK: - DER Reader

struct DERReader {
    private let bytes: [UInt8]
    private var index: Int = 0

    init(data: Data) {
        self.bytes = [UInt8](data)
    }

    mutating func readTLV(expectedTag: UInt8? = nil) throws -> (tag: UInt8, value: Data) {
        let tag = try readByte()
        let length = try readLength()
        guard index + length <= bytes.count else {
            throw LLMError.invalidRequest(message: "Invalid ASN.1 structure (length out of bounds)")
        }
        let value = Data(bytes[index..<(index + length)])
        index += length

        if let expectedTag, tag != expectedTag {
            throw LLMError.invalidRequest(message: "Invalid ASN.1 structure (unexpected tag \(tag))")
        }
        return (tag: tag, value: value)
    }

    private mutating func readByte() throws -> UInt8 {
        guard index < bytes.count else {
            throw LLMError.invalidRequest(message: "Invalid ASN.1 structure (unexpected end)")
        }
        let byte = bytes[index]
        index += 1
        return byte
    }

    private mutating func readLength() throws -> Int {
        let first = try readByte()
        if first & 0x80 == 0 {
            return Int(first)
        }

        let lengthByteCount = Int(first & 0x7F)
        guard lengthByteCount > 0 else {
            throw LLMError.invalidRequest(message: "Invalid ASN.1 structure (indefinite length)")
        }
        guard index + lengthByteCount <= bytes.count else {
            throw LLMError.invalidRequest(message: "Invalid ASN.1 structure (length out of bounds)")
        }

        var length = 0
        for _ in 0..<lengthByteCount {
            length = (length << 8) | Int(bytes[index])
            index += 1
        }
        return length
    }
}
