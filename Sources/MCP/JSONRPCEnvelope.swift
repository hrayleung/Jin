import Foundation

struct JSONRPCEnvelope: Decodable, Sendable {
    let jsonrpc: String?
    let id: JSONRPCID?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: JSONRPCErrorObject?
}

enum JSONRPCID: Decodable, Hashable, Sendable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int.self) {
            self = .int(int)
            return
        }

        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSON-RPC id")
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .string(let value):
            return Int(value)
        }
    }
}

struct JSONRPCErrorObject: Decodable, Sendable {
    let code: Int?
    let message: String
    let data: JSONValue?
}

struct JSONRPCRequest: Encodable, Sendable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: JSONValue?
}

struct JSONRPCNotification: Encodable, Sendable {
    let jsonrpc: String = "2.0"
    let method: String
    let params: JSONValue?
}

