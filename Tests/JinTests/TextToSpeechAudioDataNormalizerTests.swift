import Foundation
import XCTest
@testable import Jin

final class TextToSpeechAudioDataNormalizerTests: XCTestCase {
    func testOpenAIWrapsPCMAtExpectedSampleRate() {
        let normalized = TextToSpeechAudioDataNormalizer.openAIData(
            Data([0x01, 0x02]),
            responseFormat: " PCM "
        )

        XCTAssertEqual(sampleRate(inWAVData: normalized), 24_000)
        XCTAssertEqual(dataByteCount(inWAVData: normalized), 2)
    }

    func testOpenAIReturnsEncodedFormatsUnchanged() {
        let original = Data([0xAA, 0xBB, 0xCC])

        XCTAssertEqual(
            TextToSpeechAudioDataNormalizer.openAIData(original, responseFormat: "mp3"),
            original
        )
    }

    func testElevenLabsWrapsPCMUsingOutputFormatSampleRate() {
        let normalized = TextToSpeechAudioDataNormalizer.elevenLabsData(
            Data([0x01, 0x02]),
            outputFormat: "pcm_44100"
        )

        XCTAssertEqual(sampleRate(inWAVData: normalized), 44_100)
        XCTAssertEqual(dataByteCount(inWAVData: normalized), 2)
    }

    func testElevenLabsLeavesNonPCMAndInvalidPCMFormatsUnchanged() {
        let original = Data([0x01, 0x02, 0x03])

        XCTAssertEqual(TextToSpeechAudioDataNormalizer.elevenLabsData(original, outputFormat: "mp3_44100"), original)
        XCTAssertEqual(TextToSpeechAudioDataNormalizer.elevenLabsData(original, outputFormat: "pcm_fast"), original)
        XCTAssertEqual(TextToSpeechAudioDataNormalizer.elevenLabsData(original, outputFormat: nil), original)
    }

    func testMiMoWrapsPCMFormatsAtExpectedSampleRate() {
        let pcm = TextToSpeechAudioDataNormalizer.miMoData(Data([0x01, 0x02]), responseFormat: "pcm")
        let pcm16 = TextToSpeechAudioDataNormalizer.miMoData(Data([0x03, 0x04]), responseFormat: " PCM16 ")

        XCTAssertEqual(sampleRate(inWAVData: pcm), 24_000)
        XCTAssertEqual(sampleRate(inWAVData: pcm16), 24_000)
        XCTAssertEqual(dataByteCount(inWAVData: pcm), 2)
        XCTAssertEqual(dataByteCount(inWAVData: pcm16), 2)
    }

    func testMiMoReturnsEncodedFormatsUnchanged() {
        let original = Data([0xAA, 0xBB, 0xCC])

        XCTAssertEqual(
            TextToSpeechAudioDataNormalizer.miMoData(original, responseFormat: "wav"),
            original
        )
    }

    private func sampleRate(inWAVData data: Data) -> UInt32 {
        uint32LE([UInt8](data), at: 24)
    }

    private func dataByteCount(inWAVData data: Data) -> UInt32 {
        uint32LE([UInt8](data), at: 40)
    }

    private func uint32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}
