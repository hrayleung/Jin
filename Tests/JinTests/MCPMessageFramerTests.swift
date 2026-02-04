import XCTest
@testable import Jin

final class MCPMessageFramerTests: XCTestCase {
    func testNextMessageParsesCRLFFrame() throws {
        var framer = MCPMessageFramer()

        let payload = Data(#"{"jsonrpc":"2.0","id":1,"result":{"ok":true}}"#.utf8)
        let framed = MCPMessageFramer.frame(payload)

        framer.append(framed)
        let message = try XCTUnwrap(framer.nextMessage())
        XCTAssertEqual(message, payload)
        XCTAssertNil(try framer.nextMessage())
        XCTAssertNil(framer.drainPreamble())
    }

    func testNextMessageParsesLFDelimiter() throws {
        var framer = MCPMessageFramer()

        let payload = Data(#"{"jsonrpc":"2.0","id":1,"result":{"ok":true}}"#.utf8)
        var framed = Data()
        framed.append("Content-Length: \(payload.count)\n\n".data(using: .utf8)!)
        framed.append(payload)

        framer.append(framed)
        let message = try XCTUnwrap(framer.nextMessage())
        XCTAssertEqual(message, payload)
        XCTAssertNil(try framer.nextMessage())
    }

    func testDropsPreambleBeforeContentLength() throws {
        var framer = MCPMessageFramer()

        let preamble = Data("npm notice preamble\n".utf8)
        let payload = Data(#"{"jsonrpc":"2.0","id":1,"result":{}}"#.utf8)
        let framed = MCPMessageFramer.frame(payload)

        framer.append(preamble + framed)

        let message = try XCTUnwrap(framer.nextMessage())
        XCTAssertEqual(message, payload)

        let drainedPreamble = try XCTUnwrap(framer.drainPreamble())
        XCTAssertEqual(drainedPreamble, preamble)
    }

    func testMessageTooLargeThrows() throws {
        var framer = MCPMessageFramer(maxPreambleBytes: 1024, maxMessageBytes: 4)
        let payload = Data("12345".utf8)
        let framed = MCPMessageFramer.frame(payload)
        framer.append(framed)
        XCTAssertThrowsError(try framer.nextMessage())
    }
}

