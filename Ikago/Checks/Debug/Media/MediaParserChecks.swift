import Foundation

/// The media translation layer reads MP4 files straight from X's pages. A damaged or hostile file must make
/// `MediaTranslator.translate` return nil (the page then plays it another way), never trap and end Ikago.
/// Targeted cases cover each number the parser hands on; a seeded fuzz then corrupts valid segments at random.
/// Passing means the process is still alive at the end: a trap ends the run without the PASS line.
@MainActor
enum MediaParserChecks {
    static func run(iterations: Int = 4000) {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST mediaparser \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        func translate(_ bytes: [UInt8], stream: String) -> Data? {
            MediaTranslator.shared.translate(stream: stream, Data(bytes), urgent: false)
        }

        // A valid AAC init segment translates; that makes the broken variants below meaningful.
        check(translate(Fixture.aacInit(), stream: "parser-valid") != nil, "a valid AAC init segment translates")

        let cases: [(String, [UInt8])] = [
            ("timescale above Int32", Fixture.aacInit(timescale: 0xFFFF_FFFF)),
            ("timescale zero", Fixture.aacInit(timescale: 0)),
            ("no audio channels", Fixture.aacInit(audioConfig: [0x12, 0x00])),
            ("H.264 picture of zero size", Fixture.avcInit(width: 0, height: 0)),
            ("H.264 timescale above Int32", Fixture.avcInit(width: 640, height: 360, timescale: 0xFFFF_FFFF)),
            ("box size near the end of Int", Fixture.box("moov", Fixture.largeSize(UInt64.max))),
            ("box size past the data", Fixture.box("moov", []).dropLastSizes(0x7FFF_FFF0)),
        ]
        for (title, bytes) in cases { check(translate(bytes, stream: "parser-\(title)") == nil, "\(title) is refused") }

        let fragments: [(String, [UInt8])] = [
            ("decode time above Int64", Fixture.fragment(decodeTime: UInt64.max)),
            ("decode time near Int64's end", Fixture.fragment(decodeTime: UInt64(Int64.max) - 10)),
            ("base offset near the end of Int", Fixture.fragment(base: UInt64.max - 4)),
            ("negative data offset", Fixture.fragment(dataOffset: -1_000_000)),
            ("sample larger than the data", Fixture.fragment(sampleSize: 0xFFFF_FFF0)),
            ("huge sample duration", Fixture.fragment(sampleDuration: 0xFFFF_FFFF)),
        ]
        for (title, bytes) in fragments {
            let stream = "parser-fragment-\(title)"
            _ = translate(Fixture.aacInit(), stream: stream)
            _ = translate(bytes, stream: stream)  // refused or translated, but alive
            check(true, "\(title) doesn't end Ikago")
        }

        // Random corruption of valid segments: flipped bytes, truncation, and huge numbers at box boundaries.
        var rng = SeededRandom(seed: 0x1CA60)
        let bases = [Fixture.aacInit() + Fixture.fragment(), Fixture.avcInit(width: 640, height: 360) + Fixture.fragment(),
                     Fixture.aacInit(), Fixture.fragment()]
        var translated = 0
        for index in 0..<iterations {
            var bytes = bases[index % bases.count]
            switch rng.next() % 4 {
            case 0: for _ in 0..<(1 + rng.next() % 8) { bytes[Int(rng.next() % UInt64(bytes.count))] = UInt8(truncatingIfNeeded: rng.next()) }
            case 1: bytes = Array(bytes.prefix(Int(rng.next() % UInt64(bytes.count))))
            case 2:
                let at = Int(rng.next() % UInt64(max(1, bytes.count - 4)))
                for (offset, byte) in [0xFF, 0xFF, 0xFF, UInt8(rng.next() % 256)].enumerated() { bytes[at + offset] = byte }
            default:
                let at = Int(rng.next() % UInt64(max(1, bytes.count - 8)))
                bytes.replaceSubrange(at..<at + 8, with: Fixture.be64(rng.next()))
            }
            if translate(bytes, stream: "parser-fuzz-\(index % 5)") != nil { translated += 1 }
        }
        check(true, "\(iterations) corrupted segments didn't end Ikago (\(translated) still translated)")
        print("IKTEST mediaparserchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    /// xorshift64*, so a failing corruption replays exactly.
    struct SeededRandom {
        var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 1 : seed }
        mutating func next() -> UInt64 {
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            return state &* 0x2545_F491_4F6C_DD1D
        }
    }

    /// Hand-built fragmented MP4: just the boxes `MP4Reader` reads.
    enum Fixture {
        static func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
        static func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        static func be64(_ v: UInt64) -> [UInt8] { be32(UInt32(v >> 32)) + be32(UInt32(v & 0xFFFF_FFFF)) }
        static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] { be32(UInt32(8 + payload.count)) + Array(type.utf8) + payload }
        static func fullBox(_ type: String, version: UInt8 = 0, flags: UInt32 = 0, _ payload: [UInt8]) -> [UInt8] {
            box(type, [version] + Array(be32(flags).dropFirst()) + payload)
        }
        /// A box whose 64-bit size field says `size` (the payload is just that field's trailing bytes).
        static func largeSize(_ size: UInt64) -> [UInt8] { be32(1) + Array("free".utf8) + be64(size) }

        static func track(timescale: UInt32, entry: [UInt8]) -> [UInt8] {
            let tkhd = fullBox("tkhd", [UInt8](repeating: 0, count: 8) + be32(1) + [UInt8](repeating: 0, count: 68))
            let mdhd = fullBox("mdhd", [UInt8](repeating: 0, count: 8) + be32(timescale) + be32(0) + be16(0x55C4) + be16(0))
            let stsd = fullBox("stsd", be32(1) + entry)
            let stbl = box("stbl", stsd), minf = box("minf", stbl), mdia = box("mdia", mdhd + minf)
            let trex = fullBox("trex", be32(1) + be32(1) + be32(1024) + be32(0) + be32(0))
            return box("moov", box("trak", tkhd + mdia) + box("mvex", trex))
        }

        static func aacInit(timescale: UInt32 = 44100, audioConfig: [UInt8] = [0x12, 0x10]) -> [UInt8] {
            // ES descriptor (3) > decoder config (4) > decoder specific info (5): the AudioSpecificConfig.
            let specific = [UInt8(5), UInt8(audioConfig.count)] + audioConfig
            let config = [UInt8(4), UInt8(13 + specific.count), 0x40, 0x15] + [UInt8](repeating: 0, count: 11) + specific
            let es = [UInt8(3), UInt8(3 + config.count + 3), 0, 1, 0] + config + [6, 1, 2]
            let esds = fullBox("esds", es)
            let mp4a = box("mp4a", [UInt8](repeating: 0, count: 6) + be16(1) + [UInt8](repeating: 0, count: 8)
                           + be16(2) + be16(16) + be32(0) + be32(44100 << 16) + esds)
            return track(timescale: timescale, entry: mp4a)
        }

        static func avcInit(width: UInt16, height: UInt16, timescale: UInt32 = 90000) -> [UInt8] {
            // A minimal avcC (one tiny SPS and PPS): VideoToolbox may refuse it, which is a failed segment too.
            let avcC = box("avcC", [1, 0x42, 0, 0x1E, 0xFF, 0xE1] + be16(4) + [0x67, 0x42, 0, 0x1E] + [1] + be16(2) + [0x68, 0xCE])
            let entry = box("avc1", [UInt8](repeating: 0, count: 6) + be16(1) + [UInt8](repeating: 0, count: 16)
                            + be16(width) + be16(height) + [UInt8](repeating: 0, count: 50) + avcC)
            return track(timescale: timescale, entry: entry)
        }

        static func fragment(decodeTime: UInt64 = 0, base: UInt64? = nil, dataOffset: Int32? = nil,
                             sampleSize: UInt32 = 6, sampleDuration: UInt32 = 1024) -> [UInt8] {
            let tfhd = fullBox("tfhd", flags: base == nil ? 0x02_0000 : 0x01, be32(1) + (base.map(be64) ?? []))
            let tfdt = fullBox("tfdt", version: 1, be64(decodeTime))
            let samples = 2
            // trun with data offset, then per-sample duration and size.
            func trun(_ offset: Int32) -> [UInt8] {
                fullBox("trun", flags: 0x301, be32(UInt32(samples)) + be32(UInt32(bitPattern: offset))
                        + (0..<samples).flatMap { _ in be32(sampleDuration) + be32(sampleSize) })
            }
            let probe = box("moof", fullBox("mfhd", be32(1)) + box("traf", tfhd + tfdt + trun(0)))
            let moof = box("moof", fullBox("mfhd", be32(1)) + box("traf", tfhd + tfdt + trun(dataOffset ?? Int32(probe.count + 8))))
            return moof + box("mdat", [UInt8](repeating: 0x21, count: Int(min(sampleSize, 64)) * samples))
        }
    }
}

private extension Array where Element == UInt8 {
    /// Rewrites the first box's 32-bit size to `size`, claiming more data than there is.
    func dropLastSizes(_ size: UInt32) -> [UInt8] {
        var copy = self
        copy.replaceSubrange(0..<4, with: MediaParserChecks.Fixture.be32(size))
        return copy
    }
}
