import XCTest
import UniformTypeIdentifiers
@testable import Jin

final class ChatComposerSupportTests: XCTestCase {
    func testSpeechToTextDisplayStateReflectsRecorderState() {
        XCTAssertEqual(
            ChatComposerSupport.speechToTextSystemImageName(isRecording: false, isTranscribing: false),
            "mic"
        )
        XCTAssertEqual(
            ChatComposerSupport.speechToTextSystemImageName(isRecording: true, isTranscribing: false),
            "mic.fill"
        )
        XCTAssertEqual(
            ChatComposerSupport.speechToTextSystemImageName(isRecording: true, isTranscribing: true),
            "waveform"
        )
        XCTAssertEqual(ChatComposerSupport.speechToTextBadgeText(isTranscribing: true), "\u{2026}")
        XCTAssertNil(ChatComposerSupport.speechToTextBadgeText(isTranscribing: false))
    }

    func testSpeechToTextModeReadinessUsesAudioAttachmentOrConfiguredTranscription() {
        XCTAssertTrue(
            ChatComposerSupport.speechToTextUsesAudioAttachment(
                addRecordingAsFile: true,
                supportsAudioInput: true
            )
        )
        XCTAssertFalse(
            ChatComposerSupport.speechToTextUsesAudioAttachment(
                addRecordingAsFile: true,
                supportsAudioInput: false
            )
        )
        XCTAssertTrue(ChatComposerSupport.speechToTextReadyForCurrentMode(usesAudioAttachment: true, isConfigured: false))
        XCTAssertTrue(ChatComposerSupport.speechToTextReadyForCurrentMode(usesAudioAttachment: false, isConfigured: true))
        XCTAssertFalse(ChatComposerSupport.speechToTextReadyForCurrentMode(usesAudioAttachment: false, isConfigured: false))
    }

    func testSpeechToTextHelpTextCoversActiveDisabledAndFallbackStates() {
        XCTAssertEqual(
            ChatComposerSupport.speechToTextHelpText(
                isRecording: false,
                isTranscribing: true,
                usesAudioAttachment: true,
                isPluginEnabled: true,
                addRecordingAsFile: true,
                supportsAudioInput: true,
                isConfigured: false
            ),
            "Attaching audio\u{2026}"
        )
        XCTAssertEqual(
            ChatComposerSupport.speechToTextHelpText(
                isRecording: true,
                isTranscribing: false,
                usesAudioAttachment: false,
                isPluginEnabled: true,
                addRecordingAsFile: false,
                supportsAudioInput: false,
                isConfigured: true
            ),
            "Stop recording"
        )
        XCTAssertEqual(
            ChatComposerSupport.speechToTextHelpText(
                isRecording: false,
                isTranscribing: false,
                usesAudioAttachment: false,
                isPluginEnabled: false,
                addRecordingAsFile: false,
                supportsAudioInput: false,
                isConfigured: false
            ),
            "Speech to Text is turned off in Settings \u{2192} Plugins"
        )
        XCTAssertEqual(
            ChatComposerSupport.speechToTextHelpText(
                isRecording: false,
                isTranscribing: false,
                usesAudioAttachment: false,
                isPluginEnabled: true,
                addRecordingAsFile: true,
                supportsAudioInput: false,
                isConfigured: true
            ),
            "Current model doesn't support audio input; using transcription fallback."
        )
        XCTAssertEqual(
            ChatComposerSupport.speechToTextHelpText(
                isRecording: false,
                isTranscribing: false,
                usesAudioAttachment: false,
                isPluginEnabled: true,
                addRecordingAsFile: false,
                supportsAudioInput: true,
                isConfigured: false
            ),
            "Configure Speech to Text in Settings \u{2192} Plugins \u{2192} Speech to Text"
        )
    }

    func testComposerHelpTextAndDurationFormatting() {
        XCTAssertEqual(
            ChatComposerSupport.fileAttachmentHelpText(supportsAudioInput: true, supportsNativePDF: true),
            "Attach images / videos / audio / documents (native PDF available)"
        )
        XCTAssertEqual(
            ChatComposerSupport.fileAttachmentHelpText(supportsAudioInput: false, supportsNativePDF: false),
            "Attach images / videos / documents (PDFs may use extraction/OCR)"
        )
        XCTAssertEqual(ChatComposerSupport.artifactsHelpText(isEnabled: true), "Artifacts enabled for new replies")
        XCTAssertEqual(ChatComposerSupport.artifactsHelpText(isEnabled: false), "Enable artifact generation for new replies")
        XCTAssertEqual(ChatComposerSupport.formattedRecordingDuration(elapsedSeconds: -0.3), "0:00")
        XCTAssertEqual(ChatComposerSupport.formattedRecordingDuration(elapsedSeconds: 61.6), "1:02")
    }

    func testSupportedAttachmentImportTypesAreStableAndDeduplicated() {
        let identifiers = ChatComposerSupport.supportedAttachmentImportTypes.map(\.identifier)

        XCTAssertEqual(identifiers.count, Set(identifiers).count)
        XCTAssertTrue(identifiers.contains(UTType.image.identifier))
        XCTAssertTrue(identifiers.contains(UTType.movie.identifier))
        XCTAssertTrue(identifiers.contains(UTType.audio.identifier))
        XCTAssertTrue(identifiers.contains(UTType.pdf.identifier))
        XCTAssertEqual(ChatComposerSupport.supportedAttachmentDocumentExtensions.first, "docx")
        XCTAssertTrue(ChatComposerSupport.supportedAttachmentDocumentExtensions.contains("markdown"))
    }

    func testSlashCommandMCPServerItemNormalizesDisplayNameWithoutChangingID() {
        XCTAssertEqual(
            SlashCommandMCPServerItem(id: "github", name: " GitHub ", isSelected: false),
            SlashCommandMCPServerItem(id: "github", name: "GitHub", isSelected: false)
        )

        let fallbackToID = SlashCommandMCPServerItem(id: " github ", name: " \n ", isSelected: true)
        XCTAssertEqual(fallbackToID.id, " github ")
        XCTAssertEqual(fallbackToID.name, "github")

        let genericFallback = SlashCommandMCPServerItem(id: " \t ", name: " \n ", isSelected: false)
        XCTAssertEqual(genericFallback.id, " \t ")
        XCTAssertEqual(genericFallback.name, "MCP Server")
    }

    func testSlashCommandFilteringTrimsQueryAndMatchesNameOrID() {
        let servers = [
            SlashCommandMCPServerItem(id: "github", name: "GitHub", isSelected: false),
            SlashCommandMCPServerItem(id: "linear", name: "Issue Tracker", isSelected: true)
        ]

        XCTAssertEqual(
            SlashCommandDetection.filteredServers(servers: servers, filterText: " hub ").map(\.id),
            ["github"]
        )
        XCTAssertEqual(
            SlashCommandDetection.filteredServers(servers: servers, filterText: "\nlin\t").map(\.id),
            ["linear"]
        )
        XCTAssertEqual(
            SlashCommandDetection.filteredCount(servers: servers, filterText: " \t "),
            servers.count
        )
        XCTAssertEqual(
            SlashCommandDetection.highlightedServerID(
                servers: servers,
                filterText: " issue ",
                highlightedIndex: 4
            ),
            "linear"
        )
    }

    func testSlashCommandDetectionFindsOnlyTrailingBoundaryToken() {
        XCTAssertEqual(SlashCommandDetection.detectFilter(in: "/"), "")
        XCTAssertEqual(SlashCommandDetection.detectFilter(in: "ask /git"), "git")
        XCTAssertEqual(SlashCommandDetection.detectFilter(in: "ask /git-hub"), "git-hub")
        XCTAssertNil(SlashCommandDetection.detectFilter(in: "ask/git"))
        XCTAssertNil(SlashCommandDetection.detectFilter(in: "ask /git now"))
        XCTAssertNil(SlashCommandDetection.detectFilter(in: "ask //git"))
    }

    func testSlashCommandDetectionEdgeCases() {
        XCTAssertNil(SlashCommandDetection.detectFilter(in: ""))
        XCTAssertNil(SlashCommandDetection.detectFilter(in: "    "))
        XCTAssertNil(SlashCommandDetection.detectFilter(in: "just plain text"))
        XCTAssertNil(SlashCommandDetection.detectFilter(in: "trailing space "))
        XCTAssertEqual(SlashCommandDetection.detectFilter(in: "line one\n/git"), "git")
        XCTAssertEqual(SlashCommandDetection.detectFilter(in: "tab\there\t/git"), "git")
        XCTAssertNil(SlashCommandDetection.detectFilter(in: "line one\n/git now"))
    }

    func testSlashCommandRemovalDropsOnlyTrailingBoundaryToken() {
        XCTAssertEqual(SlashCommandDetection.removeSlashToken(from: "/git"), "")
        XCTAssertEqual(SlashCommandDetection.removeSlashToken(from: "ask /git"), "ask ")
        XCTAssertEqual(SlashCommandDetection.removeSlashToken(from: "ask/git"), "ask/git")
        XCTAssertEqual(SlashCommandDetection.removeSlashToken(from: "ask /git now"), "ask /git now")
        XCTAssertEqual(SlashCommandDetection.removeSlashToken(from: ""), "")
        XCTAssertEqual(SlashCommandDetection.removeSlashToken(from: "line one\n/git"), "line one\n")
    }

    func testMayContainActiveTokenShortCircuitsWhenSafe() {
        XCTAssertFalse(SlashCommandDetection.mayContainActiveToken(in: ""))
        XCTAssertFalse(SlashCommandDetection.mayContainActiveToken(in: "plain message without any slash"))
        XCTAssertFalse(SlashCommandDetection.mayContainActiveToken(in: "text /command was here "))
        XCTAssertTrue(SlashCommandDetection.mayContainActiveToken(in: "/"))
        XCTAssertTrue(SlashCommandDetection.mayContainActiveToken(in: "ask /git"))
        XCTAssertTrue(SlashCommandDetection.mayContainActiveToken(in: "ask/git"))
    }
}
