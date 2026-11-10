import Foundation

/// Writes the fragmented MP4 that Chromium's Media Source accepts: an init segment with one AV1 or FLAC track,
/// and media fragments whose timing matches the segment they replace.
struct MP4Writer {
    private(set) var bytes: [UInt8] = []

    mutating func u8(_ v: UInt8) { bytes.append(v) }
    mutating func u16(_ v: UInt16) { bytes += [UInt8(v >> 8), UInt8(v & 0xFF)] }
    mutating func u24(_ v: UInt32) { bytes += [UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    mutating func u32(_ v: UInt32) { bytes += [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    mutating func u64(_ v: UInt64) { u32(UInt32(v >> 32)); u32(UInt32(v & 0xFFFF_FFFF)) }
    mutating func zeros(_ n: Int) { bytes += [UInt8](repeating: 0, count: n) }
    mutating func fourCC(_ s: String) { bytes += Array(s.utf8.prefix(4)) }

    mutating func box(_ type: String, _ body: (inout MP4Writer) -> Void) {
        let start = bytes.count
        u32(0); fourCC(type)
        body(&self)
        let size = UInt32(bytes.count - start)
        bytes.replaceSubrange(start..<start + 4, with: [UInt8(size >> 24), UInt8(size >> 16 & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF)])
    }

    mutating func fullBox(_ type: String, version: UInt8 = 0, flags: UInt32 = 0, _ body: (inout MP4Writer) -> Void) {
        box(type) { w in w.u8(version); w.u24(flags); body(&w) }
    }

    static let unityMatrix: [UInt32] = [0x0001_0000, 0, 0, 0, 0x0001_0000, 0, 0, 0, 0x4000_0000]

    enum Entry {
        case av1(width: Int, height: Int, config: [UInt8])
        case flac(channels: Int, sampleRate: Int, streamInfo: [UInt8])
    }

    /// An init segment with one track.
    static func initSegment(track: UInt32, timescale: UInt32, entry: Entry) -> [UInt8] {
        var w = MP4Writer()
        let video: Bool
        if case .av1 = entry { video = true } else { video = false }
        w.box("ftyp") { w in w.fourCC("iso6"); w.u32(0); for brand in ["iso6", "iso5", "mp41", video ? "av01" : "dash"] { w.fourCC(brand) } }
        w.box("moov") { w in
            w.fullBox("mvhd") { w in
                w.u32(0); w.u32(0); w.u32(1000); w.u32(0); w.u32(0x0001_0000); w.u16(0x0100); w.zeros(10)
                unityMatrix.forEach { w.u32($0) }
                w.zeros(24); w.u32(track + 1)
            }
            w.box("trak") { w in
                w.fullBox("tkhd", flags: 3) { w in
                    w.u32(0); w.u32(0); w.u32(track); w.u32(0); w.u32(0); w.zeros(8)
                    w.u16(0); w.u16(0); w.u16(video ? 0 : 0x0100); w.u16(0)
                    unityMatrix.forEach { w.u32($0) }
                    if case let .av1(width, height, _) = entry { w.u32(UInt32(width) << 16); w.u32(UInt32(height) << 16) } else { w.u32(0); w.u32(0) }
                }
                w.box("mdia") { w in
                    w.fullBox("mdhd") { w in w.u32(0); w.u32(0); w.u32(timescale); w.u32(0); w.u16(0x55C4); w.u16(0) }
                    w.fullBox("hdlr") { w in w.u32(0); w.fourCC(video ? "vide" : "soun"); w.zeros(12); w.bytes += Array("Ikago\0".utf8) }
                    w.box("minf") { w in
                        if video { w.fullBox("vmhd", flags: 1) { w in w.zeros(8) } } else { w.fullBox("smhd") { w in w.zeros(4) } }
                        w.box("dinf") { w in w.fullBox("dref") { w in w.u32(1); w.fullBox("url ", flags: 1) { _ in } } }
                        w.box("stbl") { w in
                            w.fullBox("stsd") { w in w.u32(1); w.sampleEntry(entry) }
                            w.fullBox("stts") { w in w.u32(0) }
                            w.fullBox("stsc") { w in w.u32(0) }
                            w.fullBox("stsz") { w in w.u32(0); w.u32(0) }
                            w.fullBox("stco") { w in w.u32(0) }
                        }
                    }
                }
            }
            w.box("mvex") { w in w.fullBox("trex") { w in w.u32(track); w.u32(1); w.u32(0); w.u32(0); w.u32(0) } }
        }
        return w.bytes
    }

    private mutating func sampleEntry(_ entry: Entry) {
        switch entry {
        case let .av1(width, height, config):
            box("av01") { w in
                w.zeros(6); w.u16(1); w.zeros(16)
                w.u16(UInt16(width)); w.u16(UInt16(height))
                w.u32(0x0048_0000); w.u32(0x0048_0000); w.u32(0); w.u16(1)
                w.zeros(32); w.u16(0x0018); w.u16(0xFFFF)
                w.box("av1C") { w in w.bytes += config }
            }
        case let .flac(channels, sampleRate, streamInfo):
            box("fLaC") { w in
                w.zeros(6); w.u16(1); w.zeros(8)
                w.u16(UInt16(channels)); w.u16(16); w.u16(0); w.u16(0)
                w.u32(UInt32(sampleRate & 0xFFFF) << 16)
                w.fullBox("dfLa") { w in w.u8(0x80); w.u24(UInt32(streamInfo.count)); w.bytes += streamInfo }
            }
        }
    }

    struct OutputSample { let data: [UInt8]; let duration: UInt32; let key: Bool }

    /// One moof + mdat. `decodeTime` is in the track's timescale; samples carry no composition offsets.
    static func fragment(track: UInt32, sequence: UInt32, decodeTime: UInt64, samples: [OutputSample]) -> [UInt8] {
        var w = MP4Writer()
        var offsetPosition = 0
        w.box("moof") { w in
            w.fullBox("mfhd") { w in w.u32(sequence) }
            w.box("traf") { w in
                w.fullBox("tfhd", flags: 0x02_0000) { w in w.u32(track) }
                w.fullBox("tfdt", version: 1) { w in w.u64(decodeTime) }
                w.fullBox("trun", flags: 0x000701) { w in
                    w.u32(UInt32(samples.count))
                    offsetPosition = w.bytes.count
                    w.u32(0)
                    for sample in samples {
                        w.u32(sample.duration); w.u32(UInt32(sample.data.count))
                        w.u32(sample.key ? 0x0200_0000 : 0x0101_0000)
                    }
                }
            }
        }
        let dataOffset = UInt32(w.bytes.count + 8)
        w.bytes.replaceSubrange(offsetPosition..<offsetPosition + 4,
                                with: [UInt8(dataOffset >> 24), UInt8(dataOffset >> 16 & 0xFF), UInt8(dataOffset >> 8 & 0xFF), UInt8(dataOffset & 0xFF)])
        w.box("mdat") { w in for sample in samples { w.bytes += sample.data } }
        return w.bytes
    }
}
