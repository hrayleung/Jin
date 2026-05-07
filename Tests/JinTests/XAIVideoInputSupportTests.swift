import XCTest
@testable import Jin

final class XAIVideoInputSupportTests: XCTestCase {
    func testVideoInputPrefersLatestUserAttachedVideoOverMentionedURLAndHistory() {
        let latestVideo = VideoContent(mimeType: "video/mp4", data: Data([0x03]), url: nil)

        let selected = XAIVideoInputSupport.videoInputForVideoGeneration(from: [
            Message(role: .user, content: [
                .video(VideoContent(mimeType: "video/mp4", data: Data([0x01]), url: nil))
            ]),
            Message(role: .assistant, content: [
                .video(VideoContent(mimeType: "video/mp4", data: Data([0x02]), url: nil))
            ]),
            Message(role: .user, content: [
                .text("Use https://cdn.example.com/mentioned.mp4 as input"),
                .video(latestVideo)
            ])
        ])

        XCTAssertEqual(selected, latestVideo)
    }

    func testVideoInputUsesLatestUserMentionedRemoteVideoBeforeAssistantAndOlderUserVideos() throws {
        let remoteURL = "https://cdn.example.com/source/input.mp4?token=abc123"

        let selected = try XCTUnwrap(XAIVideoInputSupport.videoInputForVideoGeneration(from: [
            Message(role: .user, content: [
                .video(VideoContent(mimeType: "video/mp4", data: Data([0x01]), url: nil))
            ]),
            Message(role: .assistant, content: [
                .video(VideoContent(mimeType: "video/mp4", data: Data([0x02]), url: nil))
            ]),
            Message(role: .user, content: [
                .text("Use this public video URL as source: \(remoteURL)")
            ])
        ]))

        XCTAssertEqual(selected.url?.absoluteString, remoteURL)
        XCTAssertEqual(selected.mimeType, "video/mp4")
        XCTAssertEqual(selected.assetDisposition, .externalReference)
    }

    func testVideoInputFallsBackToAssistantVideoThenOlderUserVideoThenOlderMentionedURL() throws {
        let userVideo = VideoContent(mimeType: "video/mp4", data: Data([0x01]), url: nil)
        let assistantVideo = VideoContent(mimeType: "video/mp4", data: Data([0x02]), url: nil)
        let olderRemoteURL = "https://cdn.example.com/archive/video-source.webm"

        XCTAssertEqual(
            XAIVideoInputSupport.videoInputForVideoGeneration(from: [
                Message(role: .user, content: [.video(userVideo)]),
                Message(role: .assistant, content: [.video(assistantVideo)]),
                Message(role: .user, content: [.text("Apply a sharper color grade")])
            ]),
            assistantVideo
        )

        XCTAssertEqual(
            XAIVideoInputSupport.videoInputForVideoGeneration(from: [
                Message(role: .user, content: [.video(userVideo)])
            ]),
            userVideo
        )

        let selectedRemote = try XCTUnwrap(XAIVideoInputSupport.videoInputForVideoGeneration(from: [
            Message(role: .user, content: [.text("Earlier source: \(olderRemoteURL)")]),
            Message(role: .assistant, content: [.text("Ready for edits.")])
        ]))

        XCTAssertEqual(selectedRemote.url?.absoluteString, olderRemoteURL)
        XCTAssertEqual(selectedRemote.mimeType, "video/webm")
        XCTAssertEqual(selectedRemote.assetDisposition, .externalReference)
    }

    func testFirstRemoteVideoURLMentionFiltersNonRemoteAndNonVideoURLs() {
        XCTAssertNil(XAIVideoInputSupport.firstRemoteVideoURLMention(in: ""))
        XCTAssertNil(XAIVideoInputSupport.firstRemoteVideoURLMention(in: "Read https://example.com/article"))
        XCTAssertNil(XAIVideoInputSupport.firstRemoteVideoURLMention(in: "Local file file:///tmp/input.mp4"))

        XCTAssertEqual(
            XAIVideoInputSupport.firstRemoteVideoURLMention(
                in: "Use https://cdn.example.com/assets/video?id=123"
            )?.absoluteString,
            "https://cdn.example.com/assets/video?id=123"
        )
        XCTAssertEqual(
            XAIVideoInputSupport.firstRemoteVideoURLMention(
                in: "Use https://cdn.example.com/render.mov?download=1"
            )?.absoluteString,
            "https://cdn.example.com/render.mov?download=1"
        )
    }

    func testRemoteVideoURLStringOnlyAcceptsHTTPRemoteURLs() {
        XCTAssertEqual(
            XAIVideoInputSupport.remoteVideoURLString(
                VideoContent(mimeType: "video/mp4", url: URL(string: "https://cdn.example.com/source.mp4"))
            ),
            "https://cdn.example.com/source.mp4"
        )
        XCTAssertNil(
            XAIVideoInputSupport.remoteVideoURLString(
                VideoContent(mimeType: "video/mp4", url: URL(fileURLWithPath: "/tmp/source.mp4"))
            )
        )
        XCTAssertNil(
            XAIVideoInputSupport.remoteVideoURLString(
                VideoContent(mimeType: "video/mp4", url: URL(string: "ftp://cdn.example.com/source.mp4"))
            )
        )
    }
}
