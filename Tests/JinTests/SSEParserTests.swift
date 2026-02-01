import XCTest
@testable import Jin

final class SSEParserTests: XCTestCase {
    func testIgnoresEmptyDataEvent() {
        var parser = SSEParser()
        let input = "event: message\ndata:\n\n"

        for byte in input.utf8 {
            parser.append(byte)
        }

        XCTAssertNil(parser.nextEvent())
    }

    func testParsesEventTypeAndData() {
        var parser = SSEParser()
        let input = "event: message_start\ndata: {\"ok\":true}\n\n"

        for byte in input.utf8 {
            parser.append(byte)
        }

        guard let event = parser.nextEvent() else {
            XCTFail("Expected SSE event")
            return
        }

        switch event {
        case .event(let type, let data):
            XCTAssertEqual(type, "message_start")
            XCTAssertEqual(data, "{\"ok\":true}")
        case .done:
            XCTFail("Expected .event, got .done")
        }
    }

    func testParsesDoneEvent() {
        var parser = SSEParser()
        let input = "data: [DONE]\n\n"

        for byte in input.utf8 {
            parser.append(byte)
        }

        guard let event = parser.nextEvent() else {
            XCTFail("Expected SSE event")
            return
        }

        switch event {
        case .done:
            XCTAssertTrue(true)
        case .event:
            XCTFail("Expected .done, got .event")
        }
    }

    func testParsesCRLFBoundary() {
        var parser = SSEParser()
        let input = "event: message_start\r\ndata: {\"ok\":true}\r\n\r\n"

        for byte in input.utf8 {
            parser.append(byte)
        }

        guard let event = parser.nextEvent() else {
            XCTFail("Expected SSE event")
            return
        }

        switch event {
        case .event(let type, let data):
            XCTAssertEqual(type, "message_start")
            XCTAssertEqual(data, "{\"ok\":true}")
        case .done:
            XCTFail("Expected .event, got .done")
        }
    }
}
