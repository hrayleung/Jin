import XCTest
@testable import Jin

final class ClaudeManagedAgentCatalogSupportTests: XCTestCase {
    func testCollectionObjectDecodesObjectResponses() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "data": [
                ["id": "agent_123"]
            ]
        ])

        let object = try ClaudeManagedAgentCatalogSupport.collectionObject(from: data)

        XCTAssertEqual(object.array(at: ["data"])?.first?.objectValue?.string(at: ["id"]), "agent_123")
    }

    func testCollectionObjectRejectsNonObjectResponses() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            ["id": "agent_123"]
        ])

        XCTAssertThrowsError(try ClaudeManagedAgentCatalogSupport.collectionObject(from: data)) { error in
            guard case LLMError.decodingError(let message) = error else {
                return XCTFail("Expected decoding error, got \(error)")
            }
            XCTAssertTrue(message.contains("list response was not an object"))
        }
    }

    func testAgentDescriptorsParseDataItemsWithModelMetadata() throws {
        let object = try decodeObject([
            "data": [
                [
                    "id": " agent_123 ",
                    "name": " Build Agent ",
                    "model": [
                        "id": " claude-sonnet-4-6 ",
                        "display_name": " Claude Sonnet 4.6 "
                    ]
                ],
                [
                    "name": "Missing ID"
                ]
            ]
        ])

        XCTAssertEqual(
            ClaudeManagedAgentCatalogSupport.agentDescriptors(from: object),
            [
                ClaudeManagedAgentDescriptor(
                    id: "agent_123",
                    name: "Build Agent",
                    modelID: "claude-sonnet-4-6",
                    modelDisplayName: "Claude Sonnet 4.6"
                )
            ]
        )
    }

    func testAgentDescriptorsParseNestedAgentItemsAndFallbackName() throws {
        let object = try decodeObject([
            "agents": [
                [
                    "agent": [
                        "id": "agent_nested",
                        "model_id": "claude-opus-4-6"
                    ]
                ]
            ]
        ])

        XCTAssertEqual(
            ClaudeManagedAgentCatalogSupport.agentDescriptors(from: object),
            [
                ClaudeManagedAgentDescriptor(
                    id: "agent_nested",
                    name: "agent_nested",
                    modelID: "claude-opus-4-6",
                    modelDisplayName: nil
                )
            ]
        )
    }

    func testEnvironmentDescriptorsParseEnvironmentItemsAndFallbackName() throws {
        let object = try decodeObject([
            "environments": [
                [
                    "environment": [
                        "id": " env_123 ",
                        "display_name": " Production "
                    ]
                ],
                [
                    "id": "env_without_name"
                ],
                [
                    "name": "Missing ID"
                ]
            ]
        ])

        XCTAssertEqual(
            ClaudeManagedAgentCatalogSupport.environmentDescriptors(from: object),
            [
                ClaudeManagedEnvironmentDescriptor(id: "env_123", name: "Production"),
                ClaudeManagedEnvironmentDescriptor(id: "env_without_name", name: "env_without_name")
            ]
        )
    }

    func testCollectionItemsPrefersFirstNonEmptyKnownArray() throws {
        let object = try decodeObject([
            "data": [],
            "items": [
                ["id": "item_1"]
            ],
            "agents": [
                ["id": "agent_1"]
            ]
        ])

        let items = ClaudeManagedAgentCatalogSupport.collectionItems(from: object)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.string(at: ["id"]), "item_1")
    }

    private func decodeObject(_ object: [String: Any]) throws -> [String: JSONValue] {
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        return try XCTUnwrap(decoded.objectValue)
    }
}
