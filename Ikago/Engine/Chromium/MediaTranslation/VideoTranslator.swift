import CoreMedia
import Foundation
import IKCEFBridge
import VideoToolbox

/// Turns H.264 segments into AV1 ones. macOS decodes H.264 in hardware (its decoder runs in a separate system
/// process); SVT-AV1 encodes each segment independently, starting with a key frame, so segments can be appended
/// in any order and seeking works like it does with the original.
final class VideoTranslator {
    let track: UInt32
    let timescale: UInt32
    private let width: Int, height: Int
    private let format: CMVideoFormatDescription
    private var session: VTDecompressionSession?
    private var sequence: UInt32 = 0

    struct Failure: Error, CustomStringConvertible { let description: String }

    /// `fit`: the video's shorter on-screen side in device pixels (0 if unknown). A video shown at 720p or less is
    /// encoded at 720p even when the source is larger (VideoToolbox scales it while decoding): half the work for
    /// 1080p, and nothing visible is lost.
    init(track: MP4Reader.Track, fit: Int = 0) throws {
        guard case let .avc(config, width, height) = track.codec else { throw Failure(description: "not H.264") }
        self.track = track.id
        timescale = track.timescale
        let size = Self.encodedSize(width: width, height: height, fit: fit)
        self.width = size.width
        self.height = size.height
        format = try Self.formatDescription(avcC: config)
    }

    static let smallestScaledSide = 720

    static func encodedSize(width: Int, height: Int, fit: Int) -> (width: Int, height: Int) {
        let short = min(width, height)
        guard fit > 0, fit <= smallestScaledSide, short > smallestScaledSide else { return (width & ~1, height & ~1) }
        let scale = Double(smallestScaledSide) / Double(short)
        return (Int((Double(width) * scale).rounded()) & ~1, Int((Double(height) * scale).rounded()) & ~1)
    }

    deinit { if let session { VTDecompressionSessionInvalidate(session) } }

    /// The AV1 init segment. Its sequence header comes from an encoder with the same settings as every segment's.
    func initSegment() throws -> [UInt8] {
        let probe = try IKAV1Encoder(width: Int32(width), height: Int32(height), timescale: Int32(timescale),
                                     frameDuration: Int32(max(1, timescale / 30)), lowPower: true)
        let config = try AV1Config.av1C(sequenceHeaderOBUs: [UInt8](probe.sequenceHeader))
        return MP4Writer.initSegment(track: track, timescale: timescale, entry: .av1(width: width, height: height, config: config))
    }

    /// `lowPower`: the player doesn't need it yet, so use as few threads as possible (see `IKAV1Encoder`).
    func translate(_ fragment: MP4Reader.Fragment, from reader: MP4Reader, lowPower: Bool = false) throws -> [UInt8] {
        let frames = try decode(fragment, reader)
        guard !frames.isEmpty else { return [] }
        let durations = fragment.samples.map(\.duration).filter { $0 > 0 }.sorted()
        let typical = durations.isEmpty ? max(1, timescale / 30) : durations[durations.count / 2]
        let encoder = try IKAV1Encoder(width: Int32(width), height: Int32(height), timescale: Int32(timescale),
                                       frameDuration: Int32(typical), lowPower: lowPower)
        var luma = [UInt8](repeating: 0, count: width * height)
        var cb = [UInt8](repeating: 0, count: width / 2 * (height / 2)), cr = cb
        for frame in frames {
            try Self.planes(of: frame.image, width: width, height: height, luma: &luma, cb: &cb, cr: &cr)
            let sent = luma.withUnsafeBufferPointer { y in cb.withUnsafeBufferPointer { u in cr.withUnsafeBufferPointer { v in
                encoder.sendLuma(y.baseAddress!, cb: u.baseAddress!, cr: v.baseAddress!, lumaStride: Int32(width),
                                 chromaStride: Int32(width / 2), pts: frame.pts)
            } } }
            guard sent else { throw Failure(description: "the AV1 encoder refused a frame") }
        }
        let packets = encoder.finish()
        guard packets.count == frames.count else { throw Failure(description: "the AV1 encoder returned \(packets.count) of \(frames.count) frames") }
        var samples: [MP4Writer.OutputSample] = []
        for (index, packet) in packets.enumerated() {
            let next = index + 1 < frames.count ? frames[index + 1].pts : frames[index].pts + Int64(frames[index].duration)
            let duration = UInt32(clamping: max(1, next - frames[index].pts))
            samples.append(.init(data: [UInt8](packet.data), duration: duration, key: index == 0 || packet.keyFrame))
        }
        sequence &+= 1
        return MP4Writer.fragment(track: track, sequence: sequence, decodeTime: UInt64(max(0, frames[0].pts)), samples: samples)
    }

    // MARK: Decoding

    private struct Frame { let pts: Int64; let duration: UInt32; let image: CVPixelBuffer }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var frames: [(Int64, CVPixelBuffer)] = []
        func add(_ pts: Int64, _ image: CVPixelBuffer) { lock.lock(); frames.append((pts, image)); lock.unlock() }
        var all: [(Int64, CVPixelBuffer)] { lock.lock(); defer { lock.unlock() }; return frames }
    }

    private func decoder() throws -> VTDecompressionSession {
        if let session { return session }
        // Width and height make VideoToolbox scale in hardware when the encoded size is smaller than the source.
        let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                           kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height]
        var created: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(allocator: nil, formatDescription: format, decoderSpecification: nil,
                                                  imageBufferAttributes: attributes as CFDictionary, outputCallback: nil,
                                                  decompressionSessionOut: &created)
        guard status == noErr, let created else { throw Failure(description: "H.264 decoder unavailable (\(status))") }
        session = created
        return created
    }

    private func decode(_ fragment: MP4Reader.Fragment, _ reader: MP4Reader) throws -> [Frame] {
        guard fragment.samples.first?.sync == true else { throw Failure(description: "segment doesn't start with a key frame") }
        let session = try decoder()
        let collector = Collector()
        var durations: [Int64: UInt32] = [:]
        for sample in fragment.samples {
            durations[sample.composition] = sample.duration
            var block: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: sample.size, blockAllocator: nil,
                                                     customBlockSource: nil, offsetToData: 0, dataLength: sample.size, flags: 0,
                                                     blockBufferOut: &block) == noErr, let block else { continue }
            let copied = reader.bytes.withUnsafeBufferPointer { CMBlockBufferReplaceDataBytes(with: $0.baseAddress! + sample.offset, blockBuffer: block,
                                                                                               offsetIntoDestination: 0, dataLength: sample.size) }
            guard copied == noErr else { continue }
            var timing = CMSampleTimingInfo(duration: CMTime(value: Int64(sample.duration), timescale: Int32(timescale)),
                                            presentationTimeStamp: CMTime(value: sample.composition, timescale: Int32(timescale)),
                                            decodeTimeStamp: .invalid)
            var size = sample.size
            var buffer: CMSampleBuffer?
            guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
                                            sampleSizeArray: &size, sampleBufferOut: &buffer) == noErr, let buffer else { continue }
            VTDecompressionSessionDecodeFrame(session, sampleBuffer: buffer, flags: [], infoFlagsOut: nil) { status, _, image, pts, _ in
                if status == noErr, let image { collector.add(pts.value, image) }
            }
        }
        VTDecompressionSessionFinishDelayedFrames(session)
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        return collector.all.sorted { $0.0 < $1.0 }.map { Frame(pts: $0.0, duration: durations[$0.0] ?? 0, image: $0.1) }
    }

    /// NV12 from the decoder → separate 4:2:0 planes for the encoder.
    private static func planes(of image: CVPixelBuffer, width: Int, height: Int,
                               luma: inout [UInt8], cb: inout [UInt8], cr: inout [UInt8]) throws {
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard CVPixelBufferGetPlaneCount(image) == 2, CVPixelBufferGetWidth(image) >= width, CVPixelBufferGetHeight(image) >= height,
              let y = CVPixelBufferGetBaseAddressOfPlane(image, 0), let uv = CVPixelBufferGetBaseAddressOfPlane(image, 1) else {
            throw Failure(description: "unexpected decoded frame layout")
        }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(image, 0), uvStride = CVPixelBufferGetBytesPerRowOfPlane(image, 1)
        let ySource = y.assumingMemoryBound(to: UInt8.self), uvSource = uv.assumingMemoryBound(to: UInt8.self)
        luma.withUnsafeMutableBufferPointer { out in
            for row in 0..<height { (out.baseAddress! + row * width).update(from: ySource + row * yStride, count: width) }
        }
        let half = width / 2
        cb.withUnsafeMutableBufferPointer { u in cr.withUnsafeMutableBufferPointer { v in
            for row in 0..<height / 2 {
                let line = uvSource + row * uvStride
                for column in 0..<half {
                    u[row * half + column] = line[2 * column]
                    v[row * half + column] = line[2 * column + 1]
                }
            }
        } }
    }

    private static func formatDescription(avcC: [UInt8]) throws -> CMVideoFormatDescription {
        let reader = MP4Reader(bytes: avcC)
        let lengthSize = Int(try reader.u8(4) & 0x03) + 1
        var sets: [[UInt8]] = []
        var o = 5
        let spsCount = Int(try reader.u8(o) & 0x1F); o += 1
        for _ in 0..<spsCount { let n = Int(try reader.u16(o)); sets.append(try reader.slice(o + 2, n)); o += 2 + n }
        let ppsCount = Int(try reader.u8(o)); o += 1
        for _ in 0..<ppsCount { let n = Int(try reader.u16(o)); sets.append(try reader.slice(o + 2, n)); o += 2 + n }
        guard !sets.isEmpty, sets.allSatisfy({ !$0.isEmpty }) else { throw Failure(description: "no H.264 parameter sets") }
        let buffers = sets.map { set -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: set.count); p.initialize(from: set, count: set.count); return p
        }
        defer { buffers.forEach { $0.deallocate() } }
        var description: CMFormatDescription?
        let pointers = buffers.map { UnsafePointer($0) }
        let status = pointers.withUnsafeBufferPointer { p in sets.map(\.count).withUnsafeBufferPointer { sizes in
            CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: sets.count, parameterSetPointers: p.baseAddress!,
                                                                parameterSetSizes: sizes.baseAddress!, nalUnitHeaderLength: Int32(lengthSize),
                                                                formatDescriptionOut: &description)
        } }
        guard status == noErr, let description else { throw Failure(description: "invalid H.264 parameter sets (\(status))") }
        return description
    }
}
