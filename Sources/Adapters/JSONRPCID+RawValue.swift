import Foundation

extension JSONRPCID {
    var rawValue: Any {
        switch self {
        case .int(let value):
            return value
        case .string(let value):
            return value
        }
    }
}
