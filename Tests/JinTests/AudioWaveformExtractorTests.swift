import XCTest
@testable import Jin

final class AudioWaveformExtractorTests: XCTestCase {
    func testPeaksBuildNormalizedEnvelopeFromSamples() {
        let samples: [Float] = [
            0.0, 0.1, 0.4, 0.2,
            0.0, 0.3, 0.8, 0.5,
            0.0, 0.05, 0.1, 0.05,
            0.0, 0.2, 0.3, 0.1
        ]

        let peaks = AudioWaveformExtractor.peaks(
            from: samples,
            sampleRate: 4,
            secondsPerPeak: 1
        )

        XCTAssertEqual(peaks.count, 4)
        XCTAssertGreaterThan(peaks[1], 0.8)
        XCTAssertLessThan(peaks[2], peaks[1])
        XCTAssertGreaterThan(peaks[2], 0)
    }

    func testRawPeaksPreserveRelativeMagnitudesBeforeNormalization() {
        let samples: [Float] = [
            0.0, 0.1, 0.4, 0.2,
            0.0, 0.3, 0.8, 0.5
        ]

        let peaks = AudioWaveformExtractor.rawPeaks(
            from: samples,
            sampleRate: 4,
            secondsPerPeak: 1
        )

        XCTAssertEqual(peaks.count, 2)
        XCTAssertGreaterThan(peaks[0], 0)
        XCTAssertGreaterThan(peaks[1], peaks[0])
    }

    func testResampleUsesBucketMaxima() {
        let resampled = AudioWaveformExtractor.resample(
            peaks: [0.1, 0.4, 0.2, 0.9],
            targetCount: 2
        )

        XCTAssertEqual(resampled, [0.4, 0.9])
    }

    func testResampleReturnsZeroFilledOutputForEmptyWaveform() {
        let resampled = AudioWaveformExtractor.resample(peaks: [], targetCount: 4)
        XCTAssertEqual(resampled, [0, 0, 0, 0])
    }
}
