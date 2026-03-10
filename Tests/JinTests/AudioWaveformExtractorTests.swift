import Foundation
import XCTest
@testable import Jin

final class AudioWaveformExtractorTests: XCTestCase {
    func testAnalyzeDecodesWaveformFromWAVData() {
        let sampleRate = 8_000
        let frameCount = sampleRate
        let samples = (0..<frameCount).map { frame -> Int16 in
            let phase = Double(frame) * 2 * .pi * 440 / Double(sampleRate)
            let amplitude = sin(phase) * 0.6
            return Int16((amplitude * Double(Int16.max)).rounded())
        }
        let wavData = makePCM16MonoWAV(samples: samples, sampleRate: sampleRate)

        let analysis = AudioWaveformExtractor.analyze(data: wavData, secondsPerPeak: 0.1)

        XCTAssertNotNil(analysis)
        XCTAssertEqual(analysis?.rawPeaks.count, 10)
        XCTAssertGreaterThan(analysis?.rawPeaks.max() ?? 0, 0)
        XCTAssertGreaterThan(analysis?.duration ?? 0, 0.99)
        XCTAssertLessThan(analysis?.duration ?? 0, 1.01)
    }

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

    private func makePCM16MonoWAV(samples: [Int16], sampleRate: Int) -> Data {
        var pcmData = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            pcmData.appendUInt16LE(UInt16(bitPattern: sample))
        }

        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = UInt16(numChannels * (bitsPerSample / 8))
        let dataChunkSize = UInt32(pcmData.count)
        let riffChunkSize = UInt32(36) + dataChunkSize

        var header = Data()
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        header.appendUInt32LE(riffChunkSize)
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        header.appendUInt32LE(16)
        header.appendUInt16LE(1)
        header.appendUInt16LE(numChannels)
        header.appendUInt32LE(UInt32(sampleRate))
        header.appendUInt32LE(byteRate)
        header.appendUInt16LE(blockAlign)
        header.appendUInt16LE(bitsPerSample)
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.appendUInt32LE(dataChunkSize)

        var wavData = Data(capacity: header.count + pcmData.count)
        wavData.append(header)
        wavData.append(pcmData)
        return wavData
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { append(contentsOf: $0) }
    }
}
