import XCTest
@testable import Jin

final class AgentToolArgumentParserTests: XCTestCase {
    func testIntArgParsesFiniteDoublesAndTrimmedStrings() {
        XCTAssertEqual(
            AgentToolArgumentParser.intArg(["limit": 12.8], keys: ["limit"]),
            12
        )
        XCTAssertEqual(
            AgentToolArgumentParser.intArg(["limit": " 42\n"], keys: ["limit"]),
            42
        )
    }

    func testIntArgRejectsNonFiniteAndOutOfRangeDoubles() {
        XCTAssertNil(AgentToolArgumentParser.intArg(["limit": Double.nan], keys: ["limit"]))
        XCTAssertNil(AgentToolArgumentParser.intArg(["limit": Double.infinity], keys: ["limit"]))
        XCTAssertNil(AgentToolArgumentParser.intArg(["limit": -Double.infinity], keys: ["limit"]))
        XCTAssertNil(AgentToolArgumentParser.intArg(["limit": Double.greatestFiniteMagnitude], keys: ["limit"]))
    }
}
