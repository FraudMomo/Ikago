import Foundation

/// The media translation layer's native half. A page's player appends H.264/AAC fragmented MP4 to what it
/// thinks is a normal SourceBuffer; the page shim sends each append here and gets back the same media as
/// AV1/FLAC, which this Chromium plays itself. One translator per SourceBuffer ("stream"), so init segments,
/// decoders and timing state stay apart.
final class MediaTranslator: @unchecked Sendable {
    static let shared = MediaTranslator()

    private enum Translator { case video(VideoTranslator), audio(AudioTranslator) }
    private final class Stream {
        let lock = NSLock()
        var translator: Translator?
        var lastUse = Date()
    }

    private let lock = NSLock()
    private var streams: [String: Stream] = [:]
    private static let maximumStreams = 24

    /// Translates one append: any init segment and media fragments it contains, in order. Nil means the
    /// append couldn't be translated, and the shim reports an error to the page's player. `urgent`: the player is
    /// waiting for it; otherwise the encoder uses as few threads as possible. `fit`: see `VideoTranslator`.
    func translate(stream id: String, _ data: Data, urgent: Bool = true, fit: Int = 0) -> Data? {
        #if IKAGO_CHECKS
        if ProcessInfo.processInfo.environment["IKAGO_CHECKS_FAIL_TRANSLATION"] != nil { return nil }  // tests the fallback
        #endif
        let stream = self.stream(id)
        stream.lock.lock()
        defer { stream.lock.unlock() }
        stream.lastUse = Date()
        do {
            let reader = MP4Reader(bytes: [UInt8](data))
            var output: [UInt8] = []
            for box in try reader.boxes(0..<reader.bytes.count) {
                switch box.type {
                case "moov":
                    let track = try reader.track(in: box)
                    switch track.codec {
                    case .avc:
                        let video = try VideoTranslator(track: track, fit: fit)
                        output += try video.initSegment()
                        stream.translator = .video(video)
                    case .aac:
                        let audio = try AudioTranslator(track: track)
                        output += audio.initSegment()
                        stream.translator = .audio(audio)
                    }
                case "moof":
                    guard let translator = stream.translator else { throw MP4Reader.Failure(description: "media before its init segment") }
                    switch translator {
                    case .video(let video):
                        output += try video.translate(try reader.fragment(box, defaultDuration: 0), from: reader, lowPower: !urgent)
                    case .audio(let audio):
                        output += try audio.translate(try reader.fragment(box, defaultDuration: 0), from: reader)
                    }
                default:
                    continue  // ftyp, styp, sidx, mdat (read through moof), free
                }
            }
            MediaTranslation.log.info("translated \(data.count, privacy: .public) → \(output.count, privacy: .public) bytes\(urgent ? " (urgent)" : "", privacy: .public)")
            return Data(output)
        } catch {
            MediaTranslation.log.error("translation failed: \(String(describing: error), privacy: .public)")
            #if IKAGO_CHECKS || DEBUG
            print("MEDIA_TRANSLATION_FAILED \(id) \(error)")
            #endif
            return nil
        }
    }

    private func stream(_ id: String) -> Stream {
        lock.lock()
        defer { lock.unlock() }
        if let existing = streams[id] { return existing }
        if streams.count >= Self.maximumStreams, let oldest = streams.min(by: { $0.value.lastUse < $1.value.lastUse })?.key {
            streams.removeValue(forKey: oldest)
        }
        let created = Stream()
        streams[id] = created
        return created
    }
}
