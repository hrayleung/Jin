import XCTest
@testable import Jin

/// Guards the rule this whole pass exists to enforce: a `.video` content part is either
/// encoded in a shape the model accepts, or reported as omitted. It is never dropped.
///
/// The bug it replaces: a video attached to a model without video input reached the wire as
/// nothing at all, so the model answered "I don't see anything" and the attachment looked
/// like it had been sent.
final class VideoInputTranslationTests: XCTestCase {

    private let video = VideoContent(mimeType: "video/mp4", data: Data([0x00, 0x01, 0x02]), url: nil)

    // MARK: - Shared OpenAI-compatible splitting

    func testSplitContentPartsReportsVideoWhenTheModelCannotTakeIt() {
        let split = splitContentParts(
            [.text("what is this"), .video(video)],
            includeImages: true,
            includeAudio: true,
            includeVideo: false
        )

        XCTAssertFalse(split.hasRichUserContent)
        XCTAssertEqual(
            split.visible,
            "what is this\nVideo attachment omitted (video/mp4, 3 bytes): "
                + "the selected model does not accept video input."
        )
    }

    /// Most adapters join visible segments with the empty separator. Without explicit
    /// newline handling the notice welds itself onto the user's sentence.
    func testVideoNoticeIsNeverWeldedOntoTheUserText() {
        let split = splitContentParts([.text("describe this"), .video(video)], separator: "")
        XCTAssertTrue(split.visible.hasPrefix("describe this\n"), split.visible)
        XCTAssertFalse(split.visible.contains("describe thisVideo"), split.visible)
    }

    func testSplitContentPartsKeepsVideoRichWhenTheModelTakesIt() {
        let split = splitContentParts([.text("what is this"), .video(video)], includeVideo: true)
        XCTAssertTrue(split.hasRichUserContent)
        XCTAssertEqual(split.visible, "what is this")
        XCTAssertFalse(split.visible.contains("omitted"))
    }

    func testVideoOnlyMessageStillCarriesTheNotice() {
        let split = splitContentParts([.video(video)], includeVideo: false)
        XCTAssertEqual(
            split.visible,
            "Video attachment omitted (video/mp4, 3 bytes): the selected model does not accept video input."
        )
    }

    // MARK: - Shared OpenAI-compatible parts array

    func testUserContentPartsSubstituteANoticeWithoutAVideoBuilder() throws {
        let parts = try translateUserContentPartsToOpenAIFormat([.text("look"), .video(video)])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[1]["type"] as? String, "text")
        XCTAssertEqual(
            parts[1]["text"] as? String,
            "Video attachment omitted (video/mp4, 3 bytes): the selected model does not accept video input."
        )
    }

    func testUserContentPartsUseTheBuilderWhenOneIsSupplied() throws {
        let parts = try translateUserContentPartsToOpenAIFormat(
            [.text("look"), .video(video)],
            videoPartBuilder: openAIInputVideoPart
        )
        XCTAssertEqual(parts[1]["type"] as? String, "video_url")
        XCTAssertEqual(
            (parts[1]["video_url"] as? [String: Any])?["url"] as? String,
            mediaDataURI(mimeType: "video/mp4", data: Data([0x00, 0x01, 0x02]))
        )
    }

    /// A builder that cannot resolve a payload (no bytes, no readable URL) must fall back to
    /// the notice rather than returning an empty slot.
    func testUserContentPartsNoticeWhenTheBuilderResolvesNothing() throws {
        let empty = VideoContent(mimeType: "video/mp4", data: nil, url: nil)
        let parts = try translateUserContentPartsToOpenAIFormat(
            [.video(empty)],
            videoPartBuilder: openAIInputVideoPart
        )
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0]["type"] as? String, "text")
        XCTAssertTrue((parts[0]["text"] as? String)?.contains("no media payload") == true)
    }

    func testOpenAIInputVideoPartForwardsRemoteURLsUnchanged() throws {
        let remote = try XCTUnwrap(URL(string: "https://cdn.example.com/clip.mp4"))
        let part = try XCTUnwrap(openAIInputVideoPart(VideoContent(mimeType: "video/mp4", url: remote)))
        XCTAssertEqual((part["video_url"] as? [String: Any])?["url"] as? String, remote.absoluteString)
        XCTAssertNil(part["fps"], "fps / media_resolution are MiMo-only siblings")
    }

    // MARK: - Google generateContent

    func testGoogleVideoPartInlinesLocalBytes() throws {
        let part = try XCTUnwrap(GoogleVideoInputSupport.videoPart(video, allowsGoogleCloudStorageURI: false))
        let inline = try XCTUnwrap(part["inlineData"] as? [String: Any])
        XCTAssertEqual(inline["mimeType"] as? String, "video/mp4")
        XCTAssertEqual(inline["data"] as? String, Data([0x00, 0x01, 0x02]).base64EncodedString())
    }

    /// YouTube is the one remote host Google resolves server-side — verified live against
    /// `:generateContent`, which described the linked film.
    func testGoogleVideoPartForwardsYouTubeLinksAsFileData() throws {
        for link in [
            "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
            "https://youtu.be/aqz-KE-bpKQ",
            "https://m.youtube.com/watch?v=aqz-KE-bpKQ"
        ] {
            let url = try XCTUnwrap(URL(string: link))
            let part = try XCTUnwrap(
                GoogleVideoInputSupport.videoPart(
                    VideoContent(mimeType: "video/mp4", data: nil, url: url),
                    allowsGoogleCloudStorageURI: false
                ),
                link
            )
            XCTAssertEqual((part["fileData"] as? [String: Any])?["fileUri"] as? String, link)
            XCTAssertNil(part["inlineData"], link)
        }
    }

    /// Anything else remote returns nil so the caller emits a notice: Gemini answers
    /// `400 Cannot fetch content from the provided URL` for arbitrary hosts.
    func testGoogleVideoPartRefusesArbitraryRemoteURLs() throws {
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/clip.mp4"))
        XCTAssertNil(
            try GoogleVideoInputSupport.videoPart(
                VideoContent(mimeType: "video/mp4", data: nil, url: url),
                allowsGoogleCloudStorageURI: false
            )
        )
    }

    func testGoogleVideoPartAcceptsCloudStorageURIsOnVertexOnly() throws {
        let gs = try XCTUnwrap(URL(string: "gs://bucket/clip.mp4"))
        let content = VideoContent(mimeType: "video/mp4", data: nil, url: gs)

        XCTAssertNil(try GoogleVideoInputSupport.videoPart(content, allowsGoogleCloudStorageURI: false))

        let vertex = try XCTUnwrap(try GoogleVideoInputSupport.videoPart(content, allowsGoogleCloudStorageURI: true))
        XCTAssertEqual((vertex["fileData"] as? [String: Any])?["fileUri"] as? String, "gs://bucket/clip.mp4")
    }

    func testGeminiTranslationNoticesAnUnfetchableRemoteVideo() async throws {
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/clip.mp4"))
        let adapter = GeminiAdapter(
            providerConfig: ProviderConfig(id: "g", name: "Gemini", type: .gemini, apiKey: "ignored"),
            apiKey: "ignored"
        )
        let contents = try await adapter.translateContents(
            [Message(role: .user, content: [.video(VideoContent(mimeType: "video/mp4", data: nil, url: url))])],
            supportsNativePDF: false
        )
        let parts = try XCTUnwrap(contents[0]["parts"] as? [[String: Any]])

        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(
            parts[0]["text"] as? String,
            "Video attachment omitted (video/mp4, https://cdn.example.com/clip.mp4): "
                + "Gemini can only read a video from an attached file or a YouTube link, not an arbitrary URL."
        )
    }

    func testGeminiTranslationSendsYouTubeLinksThrough() async throws {
        let url = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ"))
        let adapter = GeminiAdapter(
            providerConfig: ProviderConfig(id: "g", name: "Gemini", type: .gemini, apiKey: "ignored"),
            apiKey: "ignored"
        )
        let contents = try await adapter.translateContents(
            [Message(role: .user, content: [.video(VideoContent(mimeType: "video/mp4", data: nil, url: url))])],
            supportsNativePDF: false
        )
        let parts = try XCTUnwrap(contents[0]["parts"] as? [[String: Any]])

        XCTAssertEqual((parts[0]["fileData"] as? [String: Any])?["fileUri"] as? String, url.absoluteString)
    }

    // MARK: - Cohere

    /// Cohere flattens everything to a single string, so a `.video` used to fall out of the
    /// switch entirely.
    func testCohereReportsVideoInsteadOfDroppingIt() async throws {
        let adapter = CohereAdapter(
            providerConfig: ProviderConfig(id: "c", name: "Cohere", type: .cohere, apiKey: "ignored"),
            apiKey: "ignored"
        )
        let request = try await adapter.buildRequest(
            messages: [Message(role: .user, content: [.text("what is this"), .video(video)])],
            modelID: "command-a-03-2025",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )
        let body = try XCTUnwrap(request.httpBody)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? String)
        XCTAssertTrue(content.contains("what is this"), content)
        XCTAssertTrue(content.contains("Video attachment omitted (video/mp4, 3 bytes)"), content)
    }
}
