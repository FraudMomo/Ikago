import Foundation

/// Builds the MP4 'av1C' box contents from the encoder's sequence header OBU (AV1 codec ISO-BMFF binding §2.3).
enum AV1Config {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func av1C(sequenceHeaderOBUs data: [UInt8]) throws -> [UInt8] {
        // Keep only the sequence header OBU; the encoder may lead with a temporal delimiter.
        var o = 0
        var header: [UInt8]?, payload: [UInt8] = []
        while o < data.count {
            let first = data[o]
            let type = (first >> 3) & 0x0F
            let hasExtension = first & 0x04 != 0, hasSize = first & 0x02 != 0
            var p = o + 1 + (hasExtension ? 1 : 0)
            var size = data.count - p
            if hasSize {
                size = 0
                for shift in stride(from: 0, to: 56, by: 7) {
                    guard p < data.count else { throw Failure(description: "short OBU") }
                    let b = data[p]; p += 1
                    size |= Int(b & 0x7F) << shift
                    if b & 0x80 == 0 { break }
                }
            }
            guard p + size <= data.count else { throw Failure(description: "OBU past end") }
            if type == 1 { header = Array(data[o..<p + size]); payload = Array(data[p..<p + size]) }
            o = p + size
        }
        guard let header else { throw Failure(description: "no AV1 sequence header") }
        var bits = BitReader(payload)
        let profile = try bits.read(3)
        _ = try bits.read(1)
        let reduced = try bits.read(1) == 1
        var level = 0, tier = 0
        if reduced {
            level = try bits.read(5)
        } else {
            var decoderModel = false, bufferDelayLength = 0
            if try bits.read(1) == 1 {
                _ = try bits.read(32); _ = try bits.read(32)
                if try bits.read(1) == 1 { try bits.skipUVLC() }
                decoderModel = try bits.read(1) == 1
                if decoderModel { bufferDelayLength = try bits.read(5) + 1; _ = try bits.read(32); _ = try bits.read(10) }
            }
            _ = try bits.read(1)  // initial_display_delay_present_flag; only matters after operating point 0
            _ = try bits.read(5)
            _ = try bits.read(12)
            level = try bits.read(5)
            if level > 7 { tier = try bits.read(1) }
            _ = decoderModel; _ = bufferDelayLength
        }
        guard profile == 0 else { throw Failure(description: "unexpected AV1 profile \(profile)") }
        // 8-bit 4:2:0, chroma position unknown: what the encoder is configured for.
        let flags = UInt8(tier << 7) | 0b0000_1100
        return [0x81, UInt8(profile << 5 | level), flags, 0x00] + header
    }

    private struct BitReader {
        let bytes: [UInt8]
        var position = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }
        mutating func read(_ count: Int) throws -> Int {
            var value = 0
            for _ in 0..<count {
                guard position / 8 < bytes.count else { throw Failure(description: "sequence header too short") }
                value = value << 1 | Int(bytes[position / 8] >> (7 - position % 8) & 1)
                position += 1
            }
            return value
        }
        mutating func skipUVLC() throws {
            var zeros = 0
            while try read(1) == 0 { zeros += 1; guard zeros < 32 else { return } }
            if zeros > 0 { _ = try read(zeros) }
        }
    }
}
