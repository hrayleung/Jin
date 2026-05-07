import Foundation
import XCTest
@testable import Jin

final class TextToSpeechWAVContainerTests: XCTestCase {
    func testWrapPCM16LEMonoBuildsCanonicalHeader() {
        let pcmData = Data([0x01, 0x02, 0x03, 0x04])
        let wavData = TextToSpeechWAVContainer.wrapPCM16LEMono(pcmData: pcmData, sampleRate: 24_000)
        let bytes = [UInt8](wavData)

        XCTAssertEqual(wavData.count, 48)
        XCTAssertEqual(String(decoding: bytes[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(uint32LE(bytes, at: 4), 40)
        XCTAssertEqual(String(decoding: bytes[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: bytes[12..<16], as: UTF8.self), "fmt ")
        XCTAssertEqual(uint32LE(bytes, at: 16), 16)
        XCTAssertEqual(uint16LE(bytes, at: 20), 1)
        XCTAssertEqual(uint16LE(bytes, at: 22), 1)
        XCTAssertEqual(uint32LE(bytes, at: 24), 24_000)
        XCTAssertEqual(uint32LE(bytes, at: 28), 48_000)
        XCTAssertEqual(uint16LE(bytes, at: 32), 2)
        XCTAssertEqual(uint16LE(bytes, at: 34), 16)
        XCTAssertEqual(String(decoding: bytes[36..<40], as: UTF8.self), "data")
        XCTAssertEqual(uint32LE(bytes, at: 40), 4)
        XCTAssertEqual(Array(bytes[44..<48]), [0x01, 0x02, 0x03, 0x04])
    }

    func testWrapFloat32MonoClampsAndConvertsToPCM16() {
        let wavData = TextToSpeechWAVContainer.wrapFloat32Mono(
            samples: [-2.0, -1.0, -0.5, 0.0, 0.5, 1.0, 2.0],
            sampleRate: 16_000
        )
        let bytes = [UInt8](wavData)

        XCTAssertEqual(wavData.count, 58)
        XCTAssertEqual(uint32LE(bytes, at: 40), 14)
        XCTAssertEqual(
            stride(from: 44, to: bytes.count, by: 2).map { int16LE(bytes, at: $0) },
            [-32_767, -32_767, -16_384, 0, 16_384, 32_767, 32_767]
        )
    }

    private func uint16LE(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private func uint32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    private func int16LE(_ bytes: [UInt8], at offset: Int) -> Int16 {
        Int16(bitPattern: uint16LE(bytes, at: offset))
    }
}
