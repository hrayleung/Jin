import Foundation
import XCTest
@testable import Jin

final class XAIAdapterMediaTests: XCTestCase {
    func testXAIImageGenerationBuildsRequestAndReturnsImageURL() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/images/generations")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "grok-imagine-image")
            XCTAssertEqual(root["prompt"] as? String, "A watercolor skyline")
            XCTAssertEqual(root["n"] as? Int, 2)
            XCTAssertEqual(root["aspect_ratio"] as? String, "1:1")
            XCTAssertEqual(root["response_format"] as? String, "b64_json")
            XCTAssertEqual(root["user"] as? String, "tester")
            XCTAssertEqual(root["extra_flag"] as? Bool, true)

            let response: [String: Any] = [
                "id": "img_1",
                "data": [
                    [
                        "url": "https://cdn.example.com/generated.png",
                        "mime_type": "image/png"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.text("A watercolor skyline")])
            ],
            modelID: "grok-imagine-image",
            controls: GenerationControls(
                xaiImageGeneration: XAIImageGenerationControls(
                    count: 2,
                    aspectRatio: .ratio1x1,
                    user: "tester"
                ),
                providerSpecific: ["extra_flag": AnyCodable(true)]
            ),
            tools: [],
            streaming: true
        )

        var messageStarted = false
        var generatedImages: [ImageContent] = []

        for try await event in stream {
            switch event {
            case .messageStart(let id):
                messageStarted = true
                XCTAssertEqual(id, "img_1")
            case .contentDelta(.image(let image)):
                generatedImages.append(image)
            default:
                break
            }
        }

        XCTAssertTrue(messageStarted)
        XCTAssertEqual(generatedImages.count, 1)
        XCTAssertEqual(generatedImages[0].mimeType, "image/png")
        XCTAssertEqual(generatedImages[0].url?.absoluteString, "https://cdn.example.com/generated.png")
    }

    func testXAIImageGenerationParsesBase64ImageResponse() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        let expected = Data([0x89, 0x50, 0x4e, 0x47])

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/images/generations")

            let response: [String: Any] = [
                "id": "img_2",
                "data": [
                    [
                        "b64_json": expected.base64EncodedString(),
                        "mime_type": "image/png"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("draw")])],
            modelID: "grok-imagine-image",
            controls: GenerationControls(
                xaiImageGeneration: XAIImageGenerationControls()
            ),
            tools: [],
            streaming: false
        )

        var images: [ImageContent] = []
        for try await event in stream {
            if case .contentDelta(.image(let image)) = event {
                images.append(image)
            }
        }

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].mimeType, "image/png")
        XCTAssertEqual(images[0].data, expected)
    }

    func testXAIChatFallsBackToTextForVideoInput() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/responses")
            XCTAssertEqual(request.httpMethod, "POST")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let input = try XCTUnwrap(root["input"] as? [[String: Any]])
            let first = try XCTUnwrap(input.first)
            let content = try XCTUnwrap(first["content"] as? [[String: Any]])

            let textParts = content.compactMap { item -> String? in
                guard (item["type"] as? String) == "input_text" else { return nil }
                return item["text"] as? String
            }
            XCTAssertEqual(textParts.count, 1)
            XCTAssertTrue(textParts[0].contains("Video attachment omitted"))
            XCTAssertTrue(textParts[0].contains("video/mp4"))

            let response: [String: Any] = [
                "id": "resp_1",
                "output": [
                    [
                        "type": "message",
                        "content": [
                            ["type": "output_text", "text": "OK"]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let video = VideoContent(mimeType: "video/mp4", data: Data([0x00, 0x01, 0x02]), url: nil)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.video(video)])],
            modelID: "grok-4",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testXAIImageEditUsesEditsEndpointWhenInputImageProvided() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/images/edits")
            XCTAssertEqual(request.httpMethod, "POST")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "grok-imagine-image")
            XCTAssertEqual(root["prompt"] as? String, "Make this dreamy")
            XCTAssertEqual(root["aspect_ratio"] as? String, "16:9")
            XCTAssertEqual(root["response_format"] as? String, "b64_json")
            XCTAssertNotNil(root["image_url"] as? String)

            let expected = Data([0x89, 0x50, 0x4e, 0x47])

            let response: [String: Any] = [
                "request_id": "img_edit_1",
                "images": [
                    [
                        "b64_json": expected.base64EncodedString(),
                        "mime_type": "image/png"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [
                    .text("Make this dreamy"),
                    .image(ImageContent(mimeType: "image/png", data: Data([0x01, 0x02]), url: nil))
                ])
            ],
            modelID: "grok-imagine-image",
            controls: GenerationControls(
                xaiImageGeneration: XAIImageGenerationControls(aspectRatio: .ratio16x9)
            ),
            tools: [],
            streaming: true
        )

        var messageID: String?
        var imageData: Data?

        for try await event in stream {
            switch event {
            case .messageStart(let id):
                messageID = id
            case .contentDelta(.image(let image)):
                imageData = image.data
            default:
                break
            }
        }

        XCTAssertEqual(messageID, "img_edit_1")
        XCTAssertEqual(imageData, Data([0x89, 0x50, 0x4e, 0x47]))
    }

    func testXAIFollowUpPromptUsesLatestAssistantImageForEdit() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        let priorImage = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let expected = Data([0x89, 0x50, 0x4e, 0x47])

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/images/edits")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            XCTAssertEqual(root["model"] as? String, "grok-imagine-image")
            let prompt = try XCTUnwrap(root["prompt"] as? String)
            XCTAssertTrue(prompt.contains("Original request:"))
            XCTAssertTrue(prompt.contains("girl sleeping with a cat"))
            XCTAssertTrue(prompt.contains("Apply this new edit now:"))
            XCTAssertTrue(prompt.contains("japan style"))
            XCTAssertEqual(root["response_format"] as? String, "b64_json")

            let imageURL = try XCTUnwrap(root["image_url"] as? String)
            XCTAssertTrue(imageURL.hasPrefix("data:image/png;base64,"))
            XCTAssertTrue(imageURL.contains(priorImage.base64EncodedString()))

            let response: [String: Any] = [
                "id": "img_follow_1",
                "data": [
                    [
                        "b64_json": expected.base64EncodedString(),
                        "mime_type": "image/png"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.text("girl sleeping with a cat")]),
                Message(role: .assistant, content: [
                    .image(ImageContent(mimeType: "image/png", data: priorImage, url: nil))
                ]),
                Message(role: .user, content: [.text("japan style")])
            ],
            modelID: "grok-imagine-image",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var messageID: String?
        var imageData: Data?

        for try await event in stream {
            switch event {
            case .messageStart(let id):
                messageID = id
            case .contentDelta(.image(let image)):
                imageData = image.data
            default:
                break
            }
        }

        XCTAssertEqual(messageID, "img_follow_1")
        XCTAssertEqual(imageData, expected)
    }

    func testXAIChainedEditPromptRetainsInstructionHistory() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        let priorEditedImage = Data([0xCA, 0xFE, 0xBA, 0xBE])
        let expected = Data([0x89, 0x50, 0x4e, 0x47])

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/images/edits")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let prompt = try XCTUnwrap(root["prompt"] as? String)
            XCTAssertTrue(prompt.contains("Original request:"))
            XCTAssertTrue(prompt.contains("girl sleeping with a cat"))
            XCTAssertTrue(prompt.contains("Edits already applied:"))
            XCTAssertTrue(prompt.contains("japan style"))
            XCTAssertTrue(prompt.contains("Apply this new edit now:"))
            XCTAssertTrue(prompt.contains("more realistic"))

            let imageURL = try XCTUnwrap(root["image_url"] as? String)
            XCTAssertTrue(imageURL.hasPrefix("data:image/png;base64,"))
            XCTAssertTrue(imageURL.contains(priorEditedImage.base64EncodedString()))

            let response: [String: Any] = [
                "id": "img_follow_2",
                "data": [
                    [
                        "b64_json": expected.base64EncodedString(),
                        "mime_type": "image/png"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.text("girl sleeping with a cat")]),
                Message(role: .assistant, content: [
                    .image(ImageContent(mimeType: "image/png", data: Data([0x11, 0x22]), url: nil))
                ]),
                Message(role: .user, content: [.text("japan style")]),
                Message(role: .assistant, content: [
                    .image(ImageContent(mimeType: "image/png", data: priorEditedImage, url: nil))
                ]),
                Message(role: .user, content: [.text("more realistic")])
            ],
            modelID: "grok-imagine-image",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var messageID: String?
        var imageData: Data?

        for try await event in stream {
            switch event {
            case .messageStart(let id):
                messageID = id
            case .contentDelta(.image(let image)):
                imageData = image.data
            default:
                break
            }
        }

        XCTAssertEqual(messageID, "img_follow_2")
        XCTAssertEqual(imageData, expected)
    }

    func testXAIChainedEditPrefersLatestAssistantImageOverOlderUserUpload() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        let originalUpload = Data([0x01, 0x02, 0x03])
        let assistantEdit = Data([0xAA, 0xBB, 0xCC])
        let expected = Data([0x89, 0x50, 0x4e, 0x47])

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/images/edits")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)

            let imageURL = try XCTUnwrap(root["image_url"] as? String)
            XCTAssertTrue(imageURL.hasPrefix("data:image/png;base64,"))
            XCTAssertTrue(imageURL.contains(assistantEdit.base64EncodedString()))
            XCTAssertFalse(imageURL.contains(originalUpload.base64EncodedString()))

            let response: [String: Any] = [
                "id": "img_follow_3",
                "data": [
                    [
                        "b64_json": expected.base64EncodedString(),
                        "mime_type": "image/png"
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [
                    .text("apply anime style"),
                    .image(ImageContent(mimeType: "image/png", data: originalUpload, url: nil))
                ]),
                Message(role: .assistant, content: [
                    .image(ImageContent(mimeType: "image/png", data: assistantEdit, url: nil))
                ]),
                Message(role: .user, content: [.text("make it more realistic")])
            ],
            modelID: "grok-imagine-image",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var messageID: String?
        var imageData: Data?

        for try await event in stream {
            switch event {
            case .messageStart(let id):
                messageID = id
            case .contentDelta(.image(let image)):
                imageData = image.data
            default:
                break
            }
        }

        XCTAssertEqual(messageID, "img_follow_3")
        XCTAssertEqual(imageData, expected)
    }

    func testXAIVideoGenerationSubmitsToVideosEndpointWithControls() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                XCTAssertEqual(request.url?.absoluteString, "https://example.com/videos/generations")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

                let body = try XCTUnwrap(requestBodyData(request))
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                let root = try XCTUnwrap(json)

                XCTAssertEqual(root["model"] as? String, "grok-imagine-video")
                XCTAssertEqual(root["prompt"] as? String, "A cat playing piano")
                XCTAssertEqual(root["duration"] as? Int, 5)
                XCTAssertEqual(root["aspect_ratio"] as? String, "16:9")
                XCTAssertEqual(root["resolution"] as? String, "720p")
                XCTAssertEqual(root["extra_flag"] as? Bool, true)

                let response: [String: Any] = ["request_id": "vid_req_123"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else {
                let response: [String: Any] = ["status": "expired"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("A cat playing piano")])],
            modelID: "grok-imagine-video",
            controls: GenerationControls(
                xaiVideoGeneration: XAIVideoGenerationControls(
                    duration: 5,
                    aspectRatio: .ratio16x9,
                    resolution: .res720p
                ),
                providerSpecific: ["extra_flag": AnyCodable(true)]
            ),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        do {
            for try await event in stream { events.append(event) }
        } catch {}

        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "vid_req_123")
    }

    func testXAIVideoGenerationPollsUntilDoneAndDownloadsVideo() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        let fakeVideoBytes = Data([0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70])

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                // POST /videos/generations
                XCTAssertEqual(request.url?.absoluteString, "https://example.com/videos/generations")
                XCTAssertEqual(request.httpMethod, "POST")

                let response: [String: Any] = ["request_id": "vid_done_1"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else if requestCount == 2 {
                // GET /videos/vid_done_1 — pending
                XCTAssertTrue(request.url?.absoluteString.contains("videos/vid_done_1") == true)
                XCTAssertEqual(request.httpMethod, "GET")

                let response: [String: Any] = ["status": "pending"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else if requestCount == 3 {
                // GET /videos/vid_done_1 — done
                let response: [String: Any] = [
                    "status": "done",
                    "video": [
                        "url": "https://vidgen.example.com/video.mp4",
                        "duration": 5,
                        "respect_moderation": true
                    ],
                    "model": "grok-imagine-video"
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else {
                // GET download of the temporary video URL
                XCTAssertEqual(request.url?.absoluteString, "https://vidgen.example.com/video.mp4")
                XCTAssertEqual(request.httpMethod, "GET")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, fakeVideoBytes)
            }
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("A sunset timelapse")])],
            modelID: "grok-imagine-video",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(requestCount, 4)

        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "vid_done_1")

        // Find the video content delta
        let videoEvent = events.first { event in
            if case .contentDelta(.video) = event { return true }
            return false
        }
        guard case .contentDelta(.video(let video)) = videoEvent else {
            return XCTFail("Expected contentDelta with video")
        }
        XCTAssertEqual(video.mimeType, "video/mp4")
        XCTAssertNotNil(video.url)
        XCTAssertTrue(video.url?.isFileURL == true)

        // Verify the file was downloaded to local storage
        let localURL = try XCTUnwrap(video.url)
        let savedData = try Data(contentsOf: localURL)
        XCTAssertEqual(savedData, fakeVideoBytes)

        // Clean up
        try? FileManager.default.removeItem(at: localURL)

        guard case .messageEnd(let usage) = events.last else { return XCTFail("Expected messageEnd") }
        XCTAssertNil(usage)
    }

    func testXAIVideoGenerationHandlesExpiredStatus() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                XCTAssertEqual(request.url?.absoluteString, "https://example.com/videos/generations")

                let response: [String: Any] = ["request_id": "vid_expired_1"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else {
                XCTAssertTrue(request.url?.absoluteString.contains("videos/vid_expired_1") == true)

                let response: [String: Any] = ["status": "expired"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("generate video")])],
            modelID: "grok-imagine-video",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var caughtError: Error?
        do {
            for try await _ in stream {}
        } catch {
            caughtError = error
        }

        let llmError = try XCTUnwrap(caughtError as? LLMError)
        guard case .providerError(let code, _) = llmError else {
            return XCTFail("Expected LLMError.providerError, got \(llmError)")
        }
        XCTAssertEqual(code, "video_generation_expired")
    }

    func testXAIVideoGenerationHandlesFailedStatus() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                let response: [String: Any] = ["request_id": "vid_fail_1"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else {
                let response: [String: Any] = ["status": "failed"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("generate video")])],
            modelID: "grok-imagine-video",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var caughtError: Error?
        do {
            for try await _ in stream {}
        } catch {
            caughtError = error
        }

        let llmError = try XCTUnwrap(caughtError as? LLMError)
        guard case .providerError(let code, _) = llmError else {
            return XCTFail("Expected LLMError.providerError, got \(llmError)")
        }
        XCTAssertEqual(code, "video_generation_failed")
    }

    func testXAIImageToVideoIncludesImageObjectParameter() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                XCTAssertEqual(request.url?.absoluteString, "https://example.com/videos/generations")

                let body = try XCTUnwrap(requestBodyData(request))
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                let root = try XCTUnwrap(json)

                XCTAssertEqual(root["model"] as? String, "grok-imagine-video")
                let image = try XCTUnwrap(root["image"] as? [String: Any])
                let imageURL = try XCTUnwrap(image["url"] as? String)
                XCTAssertTrue(imageURL.hasPrefix("data:image/png;base64,"))

                let response: [String: Any] = ["request_id": "vid_img2vid_1"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else {
                let response: [String: Any] = ["status": "expired"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [
                    .text("Animate this image"),
                    .image(ImageContent(mimeType: "image/png", data: Data([0x89, 0x50, 0x4e, 0x47]), url: nil))
                ])
            ],
            modelID: "grok-imagine-video",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        do {
            for try await event in stream { events.append(event) }
        } catch {}

        guard case .messageStart(let id) = events[0] else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "vid_img2vid_1")
    }

    func testXAIVideoToVideoIncludesVideoURLAndSkipsUnsupportedControls() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)
        let (defaults, defaultsSuiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        seedCloudflareR2Defaults(defaults)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("xai-video-input-\(UUID().uuidString).mp4")
        let fakeVideo = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d])
        try fakeVideo.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var requestCount = 0
        var uploadedObjectKey: String?
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(request.url?.host, "test-account.r2.cloudflarestorage.com")
                XCTAssertTrue(request.url?.path.hasPrefix("/test-bucket/") == true)

                let objectKey = String((request.url?.path ?? "").dropFirst("/test-bucket/".count))
                uploadedObjectKey = objectKey

                let uploadBody = try XCTUnwrap(requestBodyData(request))
                XCTAssertEqual(uploadBody, fakeVideo)
                XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "video/mp4")

                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
            } else if requestCount == 2 {
                XCTAssertEqual(request.url?.host, "pub.example.com")
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-0")

                return (HTTPURLResponse(
                    url: request.url!,
                    statusCode: 206,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "video/mp4"]
                )!, Data([0x00]))
            } else if requestCount == 3 {
                XCTAssertEqual(request.url?.absoluteString, "https://example.com/videos/edits")
                XCTAssertEqual(request.httpMethod, "POST")

                let body = try XCTUnwrap(requestBodyData(request))
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                let root = try XCTUnwrap(json)

                XCTAssertEqual(root["model"] as? String, "grok-imagine-video")
                let prompt = try XCTUnwrap(root["prompt"] as? String)
                XCTAssertTrue(prompt.contains("Edit the provided input video."))
                XCTAssertTrue(prompt.contains("Keep the main subject, composition, camera motion, and timing continuity unless explicitly changed."))
                XCTAssertTrue(prompt.contains("Original request:"))
                XCTAssertTrue(prompt.contains("Apply this new edit now:"))
                XCTAssertTrue(prompt.contains("Stylize this video"))
                let video = try XCTUnwrap(root["video"] as? [String: Any])
                let videoURL = try XCTUnwrap(video["url"] as? String)
                let expectedObjectKey = try XCTUnwrap(uploadedObjectKey)
                XCTAssertEqual(videoURL, "https://pub.example.com/\(expectedObjectKey)")
                XCTAssertNil(root["image"])

                // xAI docs: these are unsupported for video editing inputs.
                XCTAssertNil(root["duration"])
                XCTAssertNil(root["aspect_ratio"])
                XCTAssertNil(root["resolution"])

                let response: [String: Any] = ["request_id": "vid_vid2vid_1"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else {
                let response: [String: Any] = ["status": "expired"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
        }

        let r2Uploader = CloudflareR2Uploader(networkManager: networkManager, defaults: defaults)
        let adapter = XAIAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: networkManager,
            r2Uploader: r2Uploader
        )

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [
                    .text("Stylize this video"),
                    .video(VideoContent(mimeType: "video/mp4", data: nil, url: tempURL))
                ])
            ],
            modelID: "grok-imagine-video",
            controls: GenerationControls(
                xaiVideoGeneration: XAIVideoGenerationControls(
                    duration: 5,
                    aspectRatio: .ratio16x9,
                    resolution: .res720p
                )
            ),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        var caughtError: Error?
        do {
            for try await event in stream { events.append(event) }
        } catch {
            caughtError = error
        }

        if let caughtError {
            let llmError = try XCTUnwrap(caughtError as? LLMError)
            guard case .providerError(let code, _) = llmError else {
                return XCTFail("Expected LLMError.providerError, got \(llmError)")
            }
            XCTAssertEqual(code, "video_generation_expired")
        }

        guard case .messageStart(let id) = events.first else { return XCTFail("Expected messageStart") }
        XCTAssertEqual(id, "vid_vid2vid_1")
    }

    func testXAIVideoToVideoLocalInputFailsWhenR2ConfigMissing() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)
        let (defaults, defaultsSuiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        AppPreferences.setPluginEnabled(true, for: "cloudflare_r2_upload", defaults: defaults)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTFail("Unexpected network call: \(request)")
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("xai-video-missing-r2-\(UUID().uuidString).mp4")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let r2Uploader = CloudflareR2Uploader(networkManager: networkManager, defaults: defaults)
        let adapter = XAIAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: networkManager,
            r2Uploader: r2Uploader
        )

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [
                    .text("Stylize this video"),
                    .video(VideoContent(mimeType: "video/mp4", data: nil, url: tempURL))
                ])
            ],
            modelID: "grok-imagine-video",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var caughtError: Error?
        do {
            for try await _ in stream {}
        } catch {
            caughtError = error
        }

        let llmError = try XCTUnwrap(caughtError as? LLMError)
        guard case .invalidRequest(let message) = llmError else {
            return XCTFail("Expected LLMError.invalidRequest, got \(llmError)")
        }

        XCTAssertTrue(message.contains("Missing Cloudflare R2 settings"))
        XCTAssertTrue(message.contains("Cloudflare R2 Upload"))
    }

    func testXAIResponsesContextCacheAndUsageCachedTokens() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/responses")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-grok-conv-id"), "conv-123")

            let body = try XCTUnwrap(requestBodyData(request))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(root["prompt_cache_key"] as? String, "stable-prefix")
            XCTAssertEqual(root["prompt_cache_retention"] as? String, "1h")
            XCTAssertEqual(root["prompt_cache_min_tokens"] as? Int, 1024)
            XCTAssertNil(root["include"])

            let response: [String: Any] = [
                "id": "resp_cached_1",
                "output": [
                    [
                        "type": "message",
                        "content": [
                            ["type": "output_text", "text": "ok"]
                        ]
                    ]
                ],
                "usage": [
                    "input_tokens": 10,
                    "output_tokens": 4,
                    "prompt_tokens_details": [
                        "cached_tokens": 6
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "grok-4-1",
            controls: GenerationControls(
                contextCache: ContextCacheControls(
                    mode: .implicit,
                    ttl: .hour1,
                    cacheKey: "stable-prefix",
                    conversationID: "conv-123",
                    minTokensThreshold: 1024
                )
            ),
            tools: [],
            streaming: false
        )

        var finalUsage: Usage?
        for try await event in stream {
            if case .messageEnd(let usage) = event {
                finalUsage = usage
            }
        }

        XCTAssertEqual(finalUsage?.inputTokens, 10)
        XCTAssertEqual(finalUsage?.outputTokens, 4)
        XCTAssertEqual(finalUsage?.cachedTokens, 6)
    }

    func testXAIModelFetchMapsImageCapabilities() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/models")
            XCTAssertEqual(request.httpMethod, "GET")

            let response: [String: Any] = [
                "data": [
                    [
                        "id": "grok-4-1-fast",
                        "input_modalities": ["text", "image"],
                        "output_modalities": ["text"],
                        "context_window": 200000
                    ],
                    [
                        "id": "grok-imagine-image",
                        "input_modalities": ["text"],
                        "output_modalities": ["image"]
                    ],
                    [
                        "id": "grok-imagine-video",
                        "input_modalities": ["text", "image"],
                        "output_modalities": ["video"]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()

        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let chat = try XCTUnwrap(byID["grok-4-1-fast"])
        XCTAssertTrue(chat.capabilities.contains(.streaming))
        XCTAssertTrue(chat.capabilities.contains(.toolCalling))
        XCTAssertTrue(chat.capabilities.contains(.vision))
        XCTAssertTrue(chat.capabilities.contains(.reasoning))
        XCTAssertTrue(chat.capabilities.contains(.promptCaching))
        XCTAssertTrue(chat.capabilities.contains(.nativePDF))
        XCTAssertEqual(chat.contextWindow, 200000)

        let image = try XCTUnwrap(byID["grok-imagine-image"])
        XCTAssertTrue(image.capabilities.contains(.imageGeneration))
        XCTAssertFalse(image.capabilities.contains(.toolCalling))

        let video = try XCTUnwrap(byID["grok-imagine-video"])
        XCTAssertTrue(video.capabilities.contains(.videoGeneration))
        XCTAssertFalse(video.capabilities.contains(.toolCalling))
        XCTAssertFalse(video.capabilities.contains(.imageGeneration))
    }

    func testXAIVideoGenerationHandlesNon2xxPollAsFailure() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                let response: [String: Any] = ["request_id": "vid_500_1"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else {
                // Poll returns HTTP 500 with no parseable status field
                let body: [String: Any] = ["message": "Internal server error"]
                let data = try JSONSerialization.data(withJSONObject: body)
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, data)
            }
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("generate video")])],
            modelID: "grok-imagine-video",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var caughtError: Error?
        do {
            for try await _ in stream {}
        } catch {
            caughtError = error
        }

        let llmError = try XCTUnwrap(caughtError as? LLMError)
        guard case .providerError(let code, _) = llmError else {
            return XCTFail("Expected LLMError.providerError, got \(llmError)")
        }
        XCTAssertEqual(code, "video_generation_failed")
    }

    func testXAIVideoGenerationSurfacesNestedFailureMessage() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                let response: [String: Any] = ["request_id": "vid_nested_fail_1"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else {
                let response: [String: Any] = [
                    "status": "failed",
                    "error": [
                        "message": "Unable to fetch video_url from remote host."
                    ]
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("generate video")])],
            modelID: "grok-imagine-video",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var caughtError: Error?
        do {
            for try await _ in stream {}
        } catch {
            caughtError = error
        }

        let llmError = try XCTUnwrap(caughtError as? LLMError)
        guard case .providerError(let code, let message) = llmError else {
            return XCTFail("Expected LLMError.providerError, got \(llmError)")
        }
        XCTAssertEqual(code, "video_poll_error")
        XCTAssertTrue(message.contains("Unable to fetch video_url"))
    }

    func testXAIVideoDownloadInfersMimeTypeFromContentType() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        let fakeVideoBytes = Data([0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70])

        var requestCount = 0
        protocolType.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                let response: [String: Any] = ["request_id": "vid_mov_1"]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else if requestCount == 2 {
                let response: [String: Any] = [
                    "status": "done",
                    "video": ["url": "https://vidgen.example.com/output", "duration": 3]
                ]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else {
                // Video download returns Content-Type: video/quicktime
                return (HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "video/quicktime; charset=binary"]
                )!, fakeVideoBytes)
            }
        }

        let adapter = XAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("Make a short clip")])],
            modelID: "grok-imagine-video",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var videoContent: VideoContent?
        for try await event in stream {
            if case .contentDelta(.video(let video)) = event {
                videoContent = video
            }
        }

        let video = try XCTUnwrap(videoContent)
        XCTAssertEqual(video.mimeType, "video/quicktime")
        XCTAssertTrue(video.url?.isFileURL == true)
        XCTAssertTrue(video.url?.pathExtension == "mov")

        // Clean up
        if let url = video.url {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - URLProtocol stubbing

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockedURLSession() -> (URLSession, MockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return (URLSession(configuration: config), MockURLProtocol.self)
}

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else { return nil }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 16 * 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        if read < 0 {
            return nil
        }
        if read == 0 {
            break
        }
        data.append(buffer, count: read)
    }

    return data
}

private func makeIsolatedUserDefaults() -> (UserDefaults, String) {
    let suiteName = "jin.tests.r2.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}

private func seedCloudflareR2Defaults(_ defaults: UserDefaults) {
    AppPreferences.setPluginEnabled(true, for: "cloudflare_r2_upload", defaults: defaults)
    defaults.set("test-account", forKey: AppPreferenceKeys.cloudflareR2AccountID)
    defaults.set("test-access-key", forKey: AppPreferenceKeys.cloudflareR2AccessKeyID)
    defaults.set("test-secret-key", forKey: AppPreferenceKeys.cloudflareR2SecretAccessKey)
    defaults.set("test-bucket", forKey: AppPreferenceKeys.cloudflareR2Bucket)
    defaults.set("https://pub.example.com", forKey: AppPreferenceKeys.cloudflareR2PublicBaseURL)
    defaults.set("jin-tests", forKey: AppPreferenceKeys.cloudflareR2KeyPrefix)
}
