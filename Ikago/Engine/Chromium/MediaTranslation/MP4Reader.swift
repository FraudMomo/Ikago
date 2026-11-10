import Foundation

/// Reads the parts of fragmented MP4 (ISO-BMFF) the media translation layer needs: an init segment's track
/// and codec setup, and the samples of a media segment. Every read is bounds-checked; the bytes come from a page.
struct MP4Reader {
    struct Failure: Error, CustomStringConvertible { let description: String }
    struct Box { let type: String; let start: Int; let content: Int; let end: Int }

    let bytes: [UInt8]

    func u8(_ o: Int) throws -> UInt8 {
        guard o >= 0, o < bytes.count else { throw Failure(description: "read past end") }
        return bytes[o]
    }
    func u16(_ o: Int) throws -> UInt16 { UInt16(try u8(o)) << 8 | UInt16(try u8(o + 1)) }
    func u24(_ o: Int) throws -> UInt32 { UInt32(try u8(o)) << 16 | UInt32(try u16(o + 1)) }
    func u32(_ o: Int) throws -> UInt32 { UInt32(try u16(o)) << 16 | UInt32(try u16(o + 2)) }
    func u64(_ o: Int) throws -> UInt64 { UInt64(try u32(o)) << 32 | UInt64(try u32(o + 4)) }
    func slice(_ o: Int, _ count: Int) throws -> [UInt8] {
        guard o >= 0, count >= 0, o + count <= bytes.count else { throw Failure(description: "slice past end") }
        return Array(bytes[o..<o + count])
    }

    func boxes(_ range: Range<Int>) throws -> [Box] {
        var found: [Box] = []
        var o = range.lowerBound
        while o + 8 <= range.upperBound {
            var size = Int(try u32(o)), header = 8
            let type = String(decoding: try slice(o + 4, 4), as: UTF8.self)
            if size == 1 { size = Int(clamping: try u64(o + 8)); header = 16 } else if size == 0 { size = range.upperBound - o }
            guard size >= header, o + size <= range.upperBound else { throw Failure(description: "bad \(type) box") }
            found.append(Box(type: type, start: o, content: o + header, end: o + size))
            o += size
        }
        return found
    }

    func child(_ box: Box, _ type: String, skip: Int = 0) throws -> Box? {
        try boxes(box.content + skip..<box.end).first { $0.type == type }
    }

    func path(_ box: Box, _ types: [String]) throws -> Box? {
        var current = box
        for type in types {
            guard let next = try child(current, type) else { return nil }
            current = next
        }
        return current
    }

    // MARK: Init segment

    enum Codec { case avc(config: [UInt8], width: Int, height: Int), aac(descriptor: [UInt8], config: [UInt8], channels: Int, sampleRate: Int) }

    struct Track { let id: UInt32; let timescale: UInt32; let codec: Codec; let defaultDuration: UInt32 }

    /// The single track of an init segment's 'moov'.
    func track(in moov: Box) throws -> Track {
        guard let trak = try child(moov, "trak"), let tkhd = try child(trak, "tkhd"),
              let mdhd = try path(trak, ["mdia", "mdhd"]), let stsd = try path(trak, ["mdia", "minf", "stbl", "stsd"]) else {
            throw Failure(description: "init segment without a track")
        }
        let id = try u8(tkhd.content) == 1 ? try u32(tkhd.content + 20) : try u32(tkhd.content + 12)
        let timescale = try u8(mdhd.content) == 1 ? try u32(mdhd.content + 20) : try u32(mdhd.content + 12)
        guard let entry = try boxes(stsd.content + 8..<stsd.end).first, timescale > 0 else { throw Failure(description: "no sample entry") }
        var defaultDuration: UInt32 = 0
        if let mvex = try child(moov, "mvex"), let trex = try boxes(mvex.content..<mvex.end).first(where: { $0.type == "trex" }) {
            defaultDuration = try u32(trex.content + 12)
        }
        switch entry.type {
        case "avc1", "avc3":
            let width = Int(try u16(entry.content + 24)), height = Int(try u16(entry.content + 26))
            guard let avcC = try boxes(entry.content + 78..<entry.end).first(where: { $0.type == "avcC" }) else { throw Failure(description: "no avcC") }
            return Track(id: id, timescale: timescale, codec: .avc(config: try slice(avcC.content, avcC.end - avcC.content), width: width, height: height),
                         defaultDuration: defaultDuration)
        case "mp4a":
            guard let esds = try boxes(entry.content + 28..<entry.end).first(where: { $0.type == "esds" }) else { throw Failure(description: "no esds") }
            let descriptor = try slice(esds.content + 4, esds.end - esds.content - 4)
            let config = try Self.decoderSpecificInfo(descriptor)
            let (rate, channels) = try Self.audioSpecificConfig(config)
            return Track(id: id, timescale: timescale, codec: .aac(descriptor: descriptor, config: config, channels: channels, sampleRate: rate),
                         defaultDuration: defaultDuration)
        default:
            throw Failure(description: "unsupported sample entry \(entry.type)")
        }
    }

    /// The AudioSpecificConfig inside an ES descriptor (tag 5 within tag 4 within tag 3).
    static func decoderSpecificInfo(_ d: [UInt8]) throws -> [UInt8] {
        let reader = MP4Reader(bytes: d)
        var o = 0
        func descriptor() throws -> (tag: UInt8, length: Int, body: Int) {
            let tag = try reader.u8(o); o += 1
            var length = 0
            for _ in 0..<4 { let b = try reader.u8(o); o += 1; length = length << 7 | Int(b & 0x7F); if b & 0x80 == 0 { break } }
            return (tag, length, o)
        }
        let es = try descriptor()
        guard es.tag == 3 else { throw Failure(description: "no ES descriptor") }
        let flags = try reader.u8(o + 2); o += 3
        if flags & 0x80 != 0 { o += 2 }
        if flags & 0x40 != 0 { o += 1 + Int(try reader.u8(o)) }
        if flags & 0x20 != 0 { o += 2 }
        let config = try descriptor()
        guard config.tag == 4 else { throw Failure(description: "no decoder config") }
        o += 13
        let specific = try descriptor()
        guard specific.tag == 5, specific.length > 0 else { throw Failure(description: "no AudioSpecificConfig") }
        return try reader.slice(specific.body, specific.length)
    }

    static func audioSpecificConfig(_ c: [UInt8]) throws -> (rate: Int, channels: Int) {
        guard c.count >= 2 else { throw Failure(description: "short AudioSpecificConfig") }
        let rates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
        let index = Int((c[0] & 0x07) << 1 | c[1] >> 7)
        let channels = Int((c[1] >> 3) & 0x0F)
        guard index < rates.count, (1...2).contains(channels) else { throw Failure(description: "unsupported AAC layout") }
        return (rates[index], channels)
    }

    // MARK: Media segment

    struct Sample { let offset: Int; let size: Int; let duration: UInt32; let composition: Int64; let sync: Bool }
    struct Fragment { let track: UInt32; let decodeTime: UInt64; let samples: [Sample] }

    func fragment(_ moof: Box, defaultDuration: UInt32) throws -> Fragment {
        guard let traf = try child(moof, "traf"), let tfhd = try child(traf, "tfhd") else { throw Failure(description: "fragment without traf") }
        let tfhdFlags = try u24(tfhd.content + 1)
        let track = try u32(tfhd.content + 4)
        var o = tfhd.content + 8
        var base = moof.start
        if tfhdFlags & 0x01 != 0 { base = Int(clamping: try u64(o)); o += 8 }
        if tfhdFlags & 0x02 != 0 { o += 4 }
        var duration = defaultDuration, size: UInt32 = 0, flags: UInt32 = 0
        if tfhdFlags & 0x08 != 0 { duration = try u32(o); o += 4 }
        if tfhdFlags & 0x10 != 0 { size = try u32(o); o += 4 }
        if tfhdFlags & 0x20 != 0 { flags = try u32(o) }
        var decodeTime: UInt64 = 0
        if let tfdt = try child(traf, "tfdt") { decodeTime = try u8(tfdt.content) == 1 ? try u64(tfdt.content + 4) : UInt64(try u32(tfdt.content + 4)) }
        var samples: [Sample] = []
        var position = base, time: Int64 = 0
        for trun in try boxes(traf.content..<traf.end) where trun.type == "trun" {
            let version = try u8(trun.content), runFlags = try u24(trun.content + 1)
            let count = Int(try u32(trun.content + 4))
            guard count < 100_000 else { throw Failure(description: "too many samples") }
            var p = trun.content + 8
            if runFlags & 0x001 != 0 { position = base + Int(Int32(bitPattern: try u32(p))); p += 4 }
            var firstFlags: UInt32?
            if runFlags & 0x004 != 0 { firstFlags = try u32(p); p += 4 }
            for index in 0..<count {
                var d = duration, s = size, f = index == 0 ? (firstFlags ?? flags) : flags, cts: Int64 = 0
                if runFlags & 0x100 != 0 { d = try u32(p); p += 4 }
                if runFlags & 0x200 != 0 { s = try u32(p); p += 4 }
                if runFlags & 0x400 != 0 { f = try u32(p); p += 4 }
                if runFlags & 0x800 != 0 { let raw = try u32(p); cts = version == 0 ? Int64(raw) : Int64(Int32(bitPattern: raw)); p += 4 }
                guard position >= 0, position + Int(s) <= bytes.count else { throw Failure(description: "sample outside data") }
                samples.append(Sample(offset: position, size: Int(s), duration: d, composition: Int64(decodeTime) + time + cts,
                                      sync: (f >> 16) & 1 == 0))
                position += Int(s)
                time += Int64(d)
            }
        }
        return Fragment(track: track, decodeTime: decodeTime, samples: samples)
    }
}
