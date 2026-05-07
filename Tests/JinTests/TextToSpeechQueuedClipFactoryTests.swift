import XCTest
@testable import Jin

final class TextToSpeechQueuedClipFactoryTests: XCTestCase {
    func testClipFromFloatSamplesWrapsAudioAndTracksDurationWithoutWaveform() {
        let clip = TextToSpeechQueuedClipFactory.clip(
            fromFloatSamples: [0, 0.5, -0.5, 1],
            sampleRate: 4
        )

        XCTAssertFalse(clip.audioData.isEmpty)
        XCTAssertEqual(clip.duration, 1)
        XCTAssertEqual(clip.waveformPeaks, [])
    }

    func testClipFromAudioDataUsesWaveformAnalysisWhenAvailable() async {
        let wavData = TextToSpeechWAVContainer.wrapFloat32Mono(
            samples: [0, 0.25, -0.5, 0.75],
            sampleRate: 4
        )

        let clip = await TextToSpeechQueuedClipFactory.clip(fromAudioData: wavData)

        XCTAssertEqual(clip.audioData, wavData)
        XCTAssertEqual(clip.duration, 1, accuracy: 0.0001)
        XCTAssertFalse(clip.waveformPeaks.isEmpty)
    }

    func testClipFromInvalidAudioDataFallsBackToZeroDurationAndNoWaveform() async {
        let data = Data([0x01, 0x02, 0x03])

        let clip = await TextToSpeechQueuedClipFactory.clip(fromAudioData: data)

        XCTAssertEqual(clip.audioData, data)
        XCTAssertEqual(clip.duration, 0)
        XCTAssertEqual(clip.waveformPeaks, [])
    }
}
