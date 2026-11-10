import AudioToolbox
import Foundation

/// Turns AAC segments into FLAC ones (lossless, so the only change is the container Chromium accepts). macOS
/// decodes the AAC; each segment is decoded after the previous segment's last packet, so the decoder starts warm
/// and segment joins are seamless.
final class AudioTranslator {
    let track: UInt32
    let timescale: UInt32
    private let channels: Int, sampleRate: Int
    private let descriptor: [UInt8]
    private var preroll: [UInt8]?
    private var lastEnd: Int64?
    private var sequence: UInt32 = 0
    private static let blockSize = 4096

    struct Failure: Error, CustomStringConvertible { let description: String }

    init(track: MP4Reader.Track) throws {
        guard case let .aac(descriptor, _, channels, sampleRate) = track.codec else { throw Failure(description: "not AAC") }
        self.track = track.id
        timescale = track.timescale
        self.channels = channels
        self.sampleRate = sampleRate
        self.descriptor = descriptor
    }

    func initSegment() -> [UInt8] {
        MP4Writer.initSegment(track: track, timescale: timescale,
                              entry: .flac(channels: channels, sampleRate: sampleRate, streamInfo: FLAC.streamInfo(sampleRate: sampleRate, channels: channels, maxBlock: Self.blockSize)))
    }

    func translate(_ fragment: MP4Reader.Fragment, from reader: MP4Reader) throws -> [UInt8] {
        guard !fragment.samples.isEmpty else { return [] }
        var packets = try fragment.samples.map { try reader.slice($0.offset, $0.size) }
        // A jump means a seek: the previous segment's last packet no longer leads into this one.
        let start = fragment.samples[0].composition
        let warm = preroll != nil && lastEnd == start
        if warm, let preroll { packets.insert(preroll, at: 0) }
        var pcm = try decode(packets)
        let skip = warm ? 1024 * channels : 0
        pcm = pcm.count > skip ? Array(pcm[skip...]) : []
        preroll = packets.last
        lastEnd = start + fragment.samples.reduce(0) { $0 + Int64($1.duration) }
        let frames = pcm.count / channels
        guard frames > 0 else { return [] }
        let firstSample = Int64(Double(start) * Double(sampleRate) / Double(timescale))
        var samples: [MP4Writer.OutputSample] = []
        var offset = 0
        while offset < frames {
            let count = min(Self.blockSize, frames - offset)
            let frame = FLAC.frame(pcm: pcm, from: offset, count: count, channels: channels, sampleRate: sampleRate,
                                   firstSample: UInt64(max(0, firstSample + Int64(offset))))
            let duration = UInt32((Int64(count) * Int64(timescale) + Int64(sampleRate) / 2) / Int64(sampleRate))
            samples.append(.init(data: frame, duration: max(1, duration), key: true))
            offset += count
        }
        sequence &+= 1
        return MP4Writer.fragment(track: track, sequence: sequence, decodeTime: UInt64(max(0, start)), samples: samples)
    }

    // MARK: AAC → 16-bit PCM

    private final class Feed {
        var packets: [[UInt8]]
        var index = 0
        var current: UnsafeMutableRawPointer?
        /// Lives as long as the feed: the converter reads it after the callback returns.
        let description = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
        init(_ packets: [[UInt8]]) { self.packets = packets; description.initialize(to: AudioStreamPacketDescription()) }
        deinit { current?.deallocate(); description.deallocate() }
    }

    private func decode(_ packets: [[UInt8]]) throws -> [Int16] {
        var input = AudioStreamBasicDescription(mSampleRate: Double(sampleRate), mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
                                                mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0,
                                                mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0)
        var output = AudioStreamBasicDescription(mSampleRate: Double(sampleRate), mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                                 mBytesPerPacket: UInt32(2 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(2 * channels),
                                                 mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 16, mReserved: 0)
        var converter: AudioConverterRef?
        guard AudioConverterNew(&input, &output, &converter) == noErr, let converter else { throw Failure(description: "no AAC decoder") }
        defer { AudioConverterDispose(converter) }
        _ = descriptor.withUnsafeBytes { AudioConverterSetProperty(converter, kAudioConverterDecompressionMagicCookie, UInt32($0.count), $0.baseAddress!) }
        let feed = Feed(packets)
        var pcm: [Int16] = []
        pcm.reserveCapacity(packets.count * 1024 * channels)
        var chunk = [Int16](repeating: 0, count: 4096 * channels)
        while true {
            var frames: UInt32 = 4096
            let status = chunk.withUnsafeMutableBytes { raw -> OSStatus in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: UInt32(channels),
                                                                                    mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
                return AudioConverterFillComplexBuffer(converter, { _, count, data, descriptions, context in
                    let feed = Unmanaged<Feed>.fromOpaque(context!).takeUnretainedValue()
                    guard feed.index < feed.packets.count else { count.pointee = 0; return 1 }  // no more input
                    let packet = feed.packets[feed.index]
                    feed.index += 1
                    feed.current?.deallocate()
                    let buffer = UnsafeMutableRawPointer.allocate(byteCount: max(1, packet.count), alignment: 1)
                    packet.withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: packet.count) }
                    feed.current = buffer
                    feed.description.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count))
                    data.pointee.mBuffers.mData = buffer
                    data.pointee.mBuffers.mDataByteSize = UInt32(packet.count)
                    data.pointee.mBuffers.mNumberChannels = UInt32(1)
                    count.pointee = 1
                    descriptions?.pointee = feed.description
                    return noErr
                }, Unmanaged.passUnretained(feed).toOpaque(), &frames, &list, nil)
            }
            pcm += chunk.prefix(Int(frames) * channels)
            if frames == 0 || (status != noErr && status != 1) { break }
        }
        return pcm
    }
}

/// FLAC with verbatim subframes: lossless, and simple enough to write exactly. Variable block-size stream, so
/// every frame carries its absolute first sample number and segments are independent.
enum FLAC {
    static func streamInfo(sampleRate: Int, channels: Int, maxBlock: Int) -> [UInt8] {
        var w = MP4Writer()
        w.u16(16); w.u16(UInt16(maxBlock)); w.u24(0); w.u24(0)
        let packed = UInt64(sampleRate & 0xFFFFF) << 44 | UInt64(channels - 1) << 41 | UInt64(15) << 36
        w.u64(packed)
        w.zeros(16)
        return w.bytes
    }

    static func frame(pcm: [Int16], from start: Int, count: Int, channels: Int, sampleRate: Int, firstSample: UInt64) -> [UInt8] {
        var b: [UInt8] = [0xFF, 0xF9, 0x70 | rateCode(sampleRate), UInt8(channels - 1) << 4 | 0b1000]
        b += codedNumber(firstSample)
        b += [UInt8((count - 1) >> 8), UInt8((count - 1) & 0xFF)]
        b.append(crc8(b))
        b.reserveCapacity(b.count + channels * (1 + 2 * count) + 2)
        for channel in 0..<channels {
            b.append(0x02)  // verbatim subframe
            for i in 0..<count {
                let v = UInt16(bitPattern: pcm[(start + i) * channels + channel])
                b.append(UInt8(v >> 8)); b.append(UInt8(v & 0xFF))
            }
        }
        let crc = crc16(b)
        b += [UInt8(crc >> 8), UInt8(crc & 0xFF)]
        return b
    }

    private static func rateCode(_ rate: Int) -> UInt8 {
        [88200: 1, 176400: 2, 192000: 3, 8000: 4, 16000: 5, 22050: 6, 24000: 7, 32000: 8, 44100: 9, 48000: 10, 96000: 11][rate] ?? 0
    }

    /// FLAC's UTF-8-like coding of the sample number.
    private static func codedNumber(_ n: UInt64) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var bytes: [UInt8] = []
        var value = n
        var count = 1
        while true {
            count += 1
            let limit: UInt64 = count == 7 ? 1 << 36 : 1 << UInt64(5 * count + 1)
            if value < limit || count == 7 { break }
        }
        for _ in 1..<count { bytes.insert(0x80 | UInt8(value & 0x3F), at: 0); value >>= 6 }
        let lead: UInt8 = count == 7 ? 0xFE : UInt8(0xFF << (8 - count) & 0xFF)
        return [lead | UInt8(value)] + bytes
    }

    private static func crc8(_ bytes: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 { crc = crc & 0x80 != 0 ? (crc << 1) ^ 0x07 : crc << 1 }
        }
        return crc
    }

    private static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 { crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x8005 : crc << 1 }
        }
        return crc
    }
}
