import XCTest
@testable import Jin

enum TestJSONHelpers {
    static func makeJSONObject(_ payload: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws -> [String: JSONValue] {
        guard case .object(let object) = try JSONValue(any: payload) else {
            XCTFail("Expected object payload", file: file, line: line)
            return [:]
        }
        return object
    }
}
