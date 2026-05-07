import Foundation

extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let array) = self else { return nil }
        return array
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let number) = self else { return nil }
        return Int(number)
    }

    var doubleValue: Double? {
        guard case .number(let number) = self else { return nil }
        return number
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func string(at path: [String]) -> String? {
        value(at: path)?.stringValue
    }

    func int(at path: [String]) -> Int? {
        value(at: path)?.intValue
    }

    func double(at path: [String]) -> Double? {
        value(at: path)?.doubleValue
    }

    func bool(at path: [String]) -> Bool? {
        value(at: path)?.boolValue
    }

    func object(at path: [String]) -> [String: JSONValue]? {
        value(at: path)?.objectValue
    }

    func array(at path: [String]) -> [JSONValue]? {
        value(at: path)?.arrayValue
    }

    func contains(inArray expected: String, at path: [String]) -> Bool {
        guard let values = array(at: path) else { return false }
        return values.contains { $0.stringValue?.lowercased() == expected.lowercased() }
    }

    private func value(at path: [String]) -> JSONValue? {
        guard !path.isEmpty else { return .object(self) }
        var current: JSONValue = .object(self)

        for key in path {
            guard case .object(let object) = current,
                  let next = object[key] else {
                return nil
            }
            current = next
        }

        return current
    }
}
