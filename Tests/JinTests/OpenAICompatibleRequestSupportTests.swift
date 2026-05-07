import XCTest
@testable import Jin

final class OpenAICompatibleRequestSupportTests: XCTestCase {
    func testAppliesSamplingAndMaxTokenControls() {
        var body: [String: Any] = [:]
        let controls = GenerationControls(
            temperature: 0.7,
            maxTokens: 2048,
            topP: 0.9
        )

        OpenAICompatibleRequestSupport.applySamplingControls(
            to: &body,
            controls: controls,
            shouldOmitSamplingControls: false
        )
        OpenAICompatibleRequestSupport.applyMaxTokens(
            to: &body,
            controls: controls,
            providerType: .openaiCompatible
        )

        XCTAssertEqual(body["temperature"] as? Double, 0.7)
        XCTAssertEqual(body["top_p"] as? Double, 0.9)
        XCTAssertEqual(body["max_tokens"] as? Int, 2048)
        XCTAssertNil(body["max_completion_tokens"])
    }

    func testOmitsSamplingAndUsesMiMoMaxCompletionTokensKey() {
        var body: [String: Any] = [:]
        let controls = GenerationControls(
            temperature: 0.7,
            maxTokens: 2048,
            topP: 0.9
        )

        OpenAICompatibleRequestSupport.applySamplingControls(
            to: &body,
            controls: controls,
            shouldOmitSamplingControls: true
        )
        OpenAICompatibleRequestSupport.applyMaxTokens(
            to: &body,
            controls: controls,
            providerType: .mimoTokenPlanOpenAI
        )

        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["top_p"])
        XCTAssertNil(body["max_tokens"])
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 2048)
    }

    func testMiMoToolObjectsBuildWebSearchBeforeFunctionTools() throws {
        let functionTool: [String: Any] = [
            "type": "function",
            "function": ["name": "lookup_status"]
        ]
        let tools = OpenAICompatibleRequestSupport.miMoToolObjects(
            webSearch: WebSearchControls(
                enabled: true,
                maxUses: 3,
                userLocation: WebSearchUserLocation(
                    city: " San Francisco ",
                    region: " California ",
                    country: " US ",
                    timezone: " America/Los_Angeles "
                )
            ),
            supportsNativeWebSearch: true,
            functionTools: [functionTool]
        )

        XCTAssertEqual(tools.count, 2)

        let webSearch = try XCTUnwrap(tools.first)
        XCTAssertEqual(webSearch["type"] as? String, "web_search")
        XCTAssertEqual(webSearch["limit"] as? Int, 3)
        XCTAssertEqual(webSearch["max_keyword"] as? Int, 3)

        let location = try XCTUnwrap(webSearch["user_location"] as? [String: Any])
        XCTAssertEqual(location["type"] as? String, "approximate")
        XCTAssertEqual(location["city"] as? String, "San Francisco")
        XCTAssertEqual(location["region"] as? String, "California")
        XCTAssertEqual(location["country"] as? String, "US")
        XCTAssertEqual(location["timezone"] as? String, "America/Los_Angeles")

        let appendedFunction = try XCTUnwrap(tools.last)
        XCTAssertEqual(appendedFunction["type"] as? String, "function")
    }

    func testMiMoToolObjectsOmitUnsupportedOrEmptyWebSearch() {
        let functionTool: [String: Any] = [
            "type": "function",
            "function": ["name": "lookup_status"]
        ]

        let unsupported = OpenAICompatibleRequestSupport.miMoToolObjects(
            webSearch: WebSearchControls(enabled: true, maxUses: 3),
            supportsNativeWebSearch: false,
            functionTools: [functionTool]
        )
        XCTAssertEqual(unsupported.count, 1)
        XCTAssertNil(unsupported.first { ($0["type"] as? String) == "web_search" })

        let disabled = OpenAICompatibleRequestSupport.miMoToolObjects(
            webSearch: WebSearchControls(enabled: false, maxUses: 3),
            supportsNativeWebSearch: true,
            functionTools: [functionTool]
        )
        XCTAssertEqual(disabled.count, 1)
        XCTAssertNil(disabled.first { ($0["type"] as? String) == "web_search" })
    }

    func testProviderSpecificOverridesSkipOpenAIServiceTierAndMergeCloudflareKimiTemplateKwargs() throws {
        var body: [String: Any] = [
            "service_tier": "priority",
            "chat_template_kwargs": ["thinking": true]
        ]
        let providerConfig = ProviderConfig(
            id: "cf",
            name: "Cloudflare AI Gateway",
            type: .cloudflareAIGateway,
            apiKey: "ignored"
        )
        let controls = GenerationControls(
            providerSpecific: [
                "service_tier": AnyCodable("flex"),
                "chat_template_kwargs": AnyCodable(["existing": "value"]),
                "extra": AnyCodable("passthrough")
            ]
        )

        OpenAICompatibleRequestSupport.applyProviderSpecificOverrides(
            to: &body,
            controls: controls,
            providerConfig: providerConfig,
            modelID: "@cf/moonshotai/kimi-k2.6"
        )

        XCTAssertEqual(body["service_tier"] as? String, "flex")
        XCTAssertEqual(body["extra"] as? String, "passthrough")

        let template = try XCTUnwrap(body["chat_template_kwargs"] as? [String: Any])
        XCTAssertEqual(template["thinking"] as? Bool, true)
        XCTAssertEqual(template["existing"] as? String, "value")

        var openAIOnlyBody: [String: Any] = ["service_tier": "priority"]
        OpenAICompatibleRequestSupport.applyProviderSpecificOverrides(
            to: &openAIOnlyBody,
            controls: controls,
            providerConfig: ProviderConfig(
                id: "openai",
                name: "OpenAI",
                type: .openai,
                apiKey: "ignored"
            ),
            modelID: "gpt-5.2"
        )
        XCTAssertEqual(openAIOnlyBody["service_tier"] as? String, "priority")
    }
}
