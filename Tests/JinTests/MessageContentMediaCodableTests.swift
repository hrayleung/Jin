import Foundation
import XCTest
@testable import Jin

final class MessageContentMediaCodableTests: XCTestCase {
    func testContentPartVideoRoundTrip() throws {
        let original: [ContentPart] = [
            .text("hello"),
            .video(VideoContent(mimeType: "video/mp4", data: Data([0x00, 0x01, 0x02]), url: nil))
        ]

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([ContentPart].self, from: encoded)

        XCTAssertEqual(decoded.count, 2)

        guard case .text(let text) = decoded[0] else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(text, "hello")

        guard case .video(let video) = decoded[1] else {
            return XCTFail("Expected video content")
        }
        XCTAssertEqual(video.mimeType, "video/mp4")
        XCTAssertEqual(video.data, Data([0x00, 0x01, 0x02]))
        XCTAssertNil(video.url)
    }

    func testGenerationControlsRoundTripIncludesXAIImageControls() throws {
        let controls = GenerationControls(
            temperature: 0.3,
            xaiImageGeneration: XAIImageGenerationControls(
                count: 2,
                aspectRatio: .ratio3x2,
                user: "tester"
            )
        )

        let encoded = try JSONEncoder().encode(controls)
        let decoded = try JSONDecoder().decode(GenerationControls.self, from: encoded)

        XCTAssertEqual(decoded.temperature, 0.3)
        XCTAssertEqual(decoded.xaiImageGeneration?.count, 2)
        XCTAssertEqual(decoded.xaiImageGeneration?.aspectRatio, .ratio3x2)
        XCTAssertEqual(decoded.xaiImageGeneration?.user, "tester")
    }

    func testGenerationControlsRoundTripIncludesAnthropicWebSearchControls() throws {
        let controls = GenerationControls(
            webSearch: WebSearchControls(
                enabled: true,
                maxUses: 7,
                allowedDomains: ["example.com", "docs.example.com"],
                blockedDomains: nil,
                userLocation: WebSearchUserLocation(
                    city: "San Francisco",
                    region: "California",
                    country: "US",
                    timezone: "America/Los_Angeles"
                ),
                dynamicFiltering: true
            )
        )

        let encoded = try JSONEncoder().encode(controls)
        let decoded = try JSONDecoder().decode(GenerationControls.self, from: encoded)

        XCTAssertEqual(decoded.webSearch?.enabled, true)
        XCTAssertEqual(decoded.webSearch?.maxUses, 7)
        XCTAssertEqual(decoded.webSearch?.allowedDomains, ["example.com", "docs.example.com"])
        XCTAssertNil(decoded.webSearch?.blockedDomains)
        XCTAssertEqual(decoded.webSearch?.userLocation?.city, "San Francisco")
        XCTAssertEqual(decoded.webSearch?.userLocation?.region, "California")
        XCTAssertEqual(decoded.webSearch?.userLocation?.country, "US")
        XCTAssertEqual(decoded.webSearch?.userLocation?.timezone, "America/Los_Angeles")
        XCTAssertEqual(decoded.webSearch?.dynamicFiltering, true)
    }

    func testGenerationControlsRoundTripIncludesSearchPluginEnginePreference() throws {
        let controls = GenerationControls(
            webSearch: WebSearchControls(enabled: true),
            searchPlugin: SearchPluginControls(
                preferJinSearch: true,
                provider: .exa,
                maxResults: 10,
                recencyDays: 7
            )
        )

        let encoded = try JSONEncoder().encode(controls)
        let decoded = try JSONDecoder().decode(GenerationControls.self, from: encoded)

        XCTAssertEqual(decoded.searchPlugin?.preferJinSearch, true)
        XCTAssertEqual(decoded.searchPlugin?.provider, .exa)
        XCTAssertEqual(decoded.searchPlugin?.maxResults, 10)
        XCTAssertEqual(decoded.searchPlugin?.recencyDays, 7)
    }

    func testLegacyXAIVideoControlFieldIsIgnored() throws {
        let legacyJSON = """
        {
          "xaiImageGeneration": {
            "count": 1
          },
          "xaiVideoGeneration": {
            "resolution": "720p",
            "durationSeconds": 8
          },
          "providerSpecific": {}
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GenerationControls.self, from: legacyJSON)
        XCTAssertEqual(decoded.xaiImageGeneration?.count, 1)
    }

    func testLegacyXAIImageControlFieldsStillDecode() throws {
        let legacyJSON = """
        {
          "xaiImageGeneration": {
            "count": 1,
            "size": "1536x1024",
            "quality": "high",
            "style": "vivid"
          },
          "providerSpecific": {}
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GenerationControls.self, from: legacyJSON)
        XCTAssertEqual(decoded.xaiImageGeneration?.count, 1)
        XCTAssertEqual(decoded.xaiImageGeneration?.size, .size1536x1024)
        XCTAssertEqual(decoded.xaiImageGeneration?.quality, .high)
        XCTAssertEqual(decoded.xaiImageGeneration?.style, .vivid)
        XCTAssertNil(decoded.xaiImageGeneration?.aspectRatio)
    }

    func testLegacyContentPartPayloadWithoutVideoStillDecodes() throws {
        let legacyJSON = """
        [
          {"type":"text","text":"hello"},
          {
            "type":"image",
            "image":{
              "mimeType":"image/png",
              "data":"AQID",
              "url":null
            }
          }
        ]
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode([ContentPart].self, from: legacyJSON)
        XCTAssertEqual(decoded.count, 2)

        guard case .text(let text) = decoded[0] else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(text, "hello")

        guard case .image(let image) = decoded[1] else {
            return XCTFail("Expected image content")
        }
        XCTAssertEqual(image.mimeType, "image/png")
        XCTAssertEqual(image.data, Data([0x01, 0x02, 0x03]))
    }
}
