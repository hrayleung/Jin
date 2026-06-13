import XCTest
@testable import Jin

/// Pins the on-the-wire Codable format of the open status enums. These values are
/// persisted inside message activities, so the encoding MUST stay a bare
/// single-value string (e.g. `"in_progress"`), never a synthesized keyed enum form.
/// Guards the RawStringCodable refactor against silently switching to enum synthesis.
final class StatusEnumWireFormatTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    func testSearchActivityStatusWireFormat() throws {
        XCTAssertEqual(try json(SearchActivityStatus.inProgress), "\"in_progress\"")
        XCTAssertEqual(try json(SearchActivityStatus.searching), "\"searching\"")
        XCTAssertEqual(try json(SearchActivityStatus.completed), "\"completed\"")
        XCTAssertEqual(try json(SearchActivityStatus.failed), "\"failed\"")
        XCTAssertEqual(try json(SearchActivityStatus.unknown("custom_state")), "\"custom_state\"")

        XCTAssertEqual(try decoder.decode(SearchActivityStatus.self, from: Data("\"in_progress\"".utf8)), .inProgress)
        XCTAssertEqual(try decoder.decode(SearchActivityStatus.self, from: Data("\"searching\"".utf8)), .searching)
        XCTAssertEqual(try decoder.decode(SearchActivityStatus.self, from: Data("\"weird\"".utf8)), .unknown("weird"))
    }

    func testCodeExecutionStatusWireFormat() throws {
        XCTAssertEqual(try json(CodeExecutionStatus.inProgress), "\"in_progress\"")
        XCTAssertEqual(try json(CodeExecutionStatus.writingCode), "\"writing_code\"")
        XCTAssertEqual(try json(CodeExecutionStatus.interpreting), "\"interpreting\"")
        XCTAssertEqual(try json(CodeExecutionStatus.completed), "\"completed\"")
        XCTAssertEqual(try json(CodeExecutionStatus.failed), "\"failed\"")
        XCTAssertEqual(try json(CodeExecutionStatus.incomplete), "\"incomplete\"")
        XCTAssertEqual(try json(CodeExecutionStatus.unknown("custom_state")), "\"custom_state\"")

        XCTAssertEqual(try decoder.decode(CodeExecutionStatus.self, from: Data("\"writing_code\"".utf8)), .writingCode)
        XCTAssertEqual(try decoder.decode(CodeExecutionStatus.self, from: Data("\"weird\"".utf8)), .unknown("weird"))
    }
}
