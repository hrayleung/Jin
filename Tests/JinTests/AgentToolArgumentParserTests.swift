import XCTest
@testable import Jin

final class AgentToolArgumentParserTests: XCTestCase {
    func testRawArgumentsUnwrapsAnyCodableValues() {
        let raw = AgentToolArgumentParser.rawArguments([
            "command": AnyCodable("pwd"),
            "limit": AnyCodable(12),
            "enabled": AnyCodable(true)
        ])

        XCTAssertEqual(raw["command"] as? String, "pwd")
        XCTAssertEqual(raw["limit"] as? Int, 12)
        XCTAssertEqual(raw["enabled"] as? Bool, true)
    }

    func testAgentToolArgumentKeysRetainSupportedAliases() {
        XCTAssertEqual(AgentToolArgumentKeys.command, ["command", "cmd"])
        XCTAssertEqual(AgentToolArgumentKeys.workingDirectory, ["working_directory", "workingDirectory", "cwd"])
        XCTAssertEqual(AgentToolArgumentKeys.filePath, ["path", "file", "file_path", "filePath"])
        XCTAssertEqual(AgentToolArgumentKeys.fileContent, ["content", "text", "data"])
        XCTAssertEqual(AgentToolArgumentKeys.fileEditOldText, ["old_text", "oldText", "old_string", "search"])
        XCTAssertEqual(AgentToolArgumentKeys.fileEditNewText, ["new_text", "newText", "new_string", "replace"])
    }

    func testRawStringArgPreservesWhitespaceAndUsesAliases() {
        XCTAssertEqual(
            AgentToolArgumentParser.rawStringArg(["content": "  keep spacing\n"], keys: ["content"]),
            "  keep spacing\n"
        )
        XCTAssertEqual(
            AgentToolArgumentParser.rawStringArg(["text": "fallback"], keys: ["content", "text"]),
            "fallback"
        )
    }

    func testNormalizedStringArgTrimsStringsAndFormatsNumericValues() {
        XCTAssertEqual(
            AgentToolArgumentParser.normalizedStringArg(["command": " git status\n"], keys: ["command"]),
            "git status"
        )
        XCTAssertEqual(
            AgentToolArgumentParser.normalizedStringArg(["offset": 12], keys: ["offset"]),
            "12"
        )
        XCTAssertEqual(
            AgentToolArgumentParser.normalizedStringArg(["limit": 12.8], keys: ["limit"]),
            "12"
        )
    }

    func testNormalizedStringArgSkipsBlankAndUnsupportedValues() {
        XCTAssertEqual(
            AgentToolArgumentParser.normalizedStringArg(
                ["command": " ", "cmd": "pwd"],
                keys: AgentToolArgumentKeys.command
            ),
            "pwd"
        )
        XCTAssertNil(AgentToolArgumentParser.normalizedStringArg(["limit": Double.nan], keys: ["limit"]))
        XCTAssertNil(AgentToolArgumentParser.normalizedStringArg(["enabled": true], keys: ["enabled"]))
    }

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
