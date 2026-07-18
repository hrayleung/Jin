import XCTest
@testable import Jin

final class SSEParserTests: XCTestCase {
    func testIgnoresEmptyDataEvent() {
        var parser = SSEParser()
        parser.append(Data("event: message\ndata:\n\n".utf8))

        XCTAssertNil(parser.nextEvent())
    }

    func testParsesEventTypeAndData() {
        var parser = SSEParser()
        parser.append(Data("event: message_start\ndata: {\"ok\":true}\n\n".utf8))

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
        parser.append(Data("data: [DONE]\n\n".utf8))

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
        parser.append(Data("event: message_start\r\ndata: {\"ok\":true}\r\n\r\n".utf8))

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

    func testFinishFlushesDoneEventWithoutTrailingBoundary() {
        var parser = SSEParser()
        parser.append(Data("data: [DONE]".utf8))
        parser.finish()

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

    func testParsesMultipleEventsInSingleChunk() {
        var parser = SSEParser()
        let chunk = """
        event: a\ndata: one\n\nevent: b\ndata: two\n\ndata: [DONE]\n\n
        """
        parser.append(Data(chunk.utf8))

        guard case .event(let typeA, let dataA)? = parser.nextEvent() else {
            XCTFail("Expected first event")
            return
        }
        XCTAssertEqual(typeA, "a")
        XCTAssertEqual(dataA, "one")

        guard case .event(let typeB, let dataB)? = parser.nextEvent() else {
            XCTFail("Expected second event")
            return
        }
        XCTAssertEqual(typeB, "b")
        XCTAssertEqual(dataB, "two")

        guard case .done? = parser.nextEvent() else {
            XCTFail("Expected done")
            return
        }
        XCTAssertNil(parser.nextEvent())
    }

    func testParsesEventSplitAcrossChunks() {
        var parser = SSEParser()
        parser.append(Data("event: message_start\ndata: {\"ok\"".utf8))
        XCTAssertNil(parser.nextEvent())

        parser.append(Data(":true}\n\n".utf8))

        guard case .event(let type, let data)? = parser.nextEvent() else {
            XCTFail("Expected SSE event after second chunk")
            return
        }
        XCTAssertEqual(type, "message_start")
        XCTAssertEqual(data, "{\"ok\":true}")
    }

    func testByteAppendStillWorks() {
        var parser = SSEParser()
        for byte in "data: hi\n\n".utf8 {
            parser.append(byte)
        }
        guard case .event(_, let data)? = parser.nextEvent() else {
            XCTFail("Expected event via byte path")
            return
        }
        XCTAssertEqual(data, "hi")
    }

    func testJSONLineParserTrimsLinesAndIgnoresBlankLines() {
        var parser = JSONLineParser()
        parser.append(Data(" \n {\"ok\":true} \n".utf8))

        XCTAssertEqual(parser.nextEvent(), "{\"ok\":true}")
        XCTAssertNil(parser.nextEvent())
    }

    func testJSONLineParserHandlesSplitLinesAndMultiLineChunks() {
        var parser = JSONLineParser()
        parser.append(Data("{\"a\":1".utf8))
        XCTAssertNil(parser.nextEvent())
        parser.append(Data("}\n{\"b\":2}\n".utf8))
        XCTAssertEqual(parser.nextEvent(), "{\"a\":1}")
        XCTAssertEqual(parser.nextEvent(), "{\"b\":2}")
        XCTAssertNil(parser.nextEvent())
    }
}
