import Foundation

enum TextToSpeechWAVContainer {
    static func wrapFloat32Mono(samples: [Float], sampleRate: Int) -> Data {
        var pcmData = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intValue = Int16((clamped * Float(Int16.max)).rounded())
            pcmData.appendUInt16LE(UInt16(bitPattern: intValue))
        }
        return wrapPCM16LEMono(pcmData: pcmData, sampleRate: sampleRate)
    }

    static func wrapPCM16LEMono(pcmData: Data, sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = UInt16(numChannels * (bitsPerSample / 8))
        let dataChunkSize = UInt32(pcmData.count)
        let riffChunkSize = UInt32(36) + dataChunkSize

        var header = Data()
        header.reserveCapacity(44)
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
