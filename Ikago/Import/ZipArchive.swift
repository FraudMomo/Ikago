import Compression
import Foundation

/// The small part of the ZIP format Ikago needs: writing an export (files stored as they are, which every unzip tool,
/// Safari and Chrome read), and reading one back, stored or deflated (what Safari, Finder and `zip` write). No ZIP64,
/// encryption or multi-part archives: exports are a few files of a few megabytes.
enum ZipArchive {
    struct Entry: Equatable {
        var name: String
        var data: Data
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static let maxEntries = 64
    /// Each file read back is capped, so a crafted archive can't inflate into gigabytes.
    static let maxEntrySize = 64_000_000

    // MARK: Writing

    static func write(_ entries: [Entry], date: Date = Date()) -> Data {
        var out = Data(), central = Data()
        let (time, day) = dosDateTime(date)
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(out.count)
            // Local file header: stored (method 0), UTF-8 names (flag bit 11).
            out.append(le32: 0x0403_4b50); out.append(le16: 20); out.append(le16: 0x0800); out.append(le16: 0)
            out.append(le16: time); out.append(le16: day); out.append(le32: crc)
            out.append(le32: size); out.append(le32: size)
            out.append(le16: UInt16(name.count)); out.append(le16: 0)
            out.append(name); out.append(entry.data)
            // Its central directory record.
            central.append(le32: 0x0201_4b50); central.append(le16: 0x0314); central.append(le16: 20)
            central.append(le16: 0x0800); central.append(le16: 0); central.append(le16: time); central.append(le16: day)
            central.append(le32: crc); central.append(le32: size); central.append(le32: size)
            central.append(le16: UInt16(name.count)); central.append(le16: 0); central.append(le16: 0)
            central.append(le16: 0); central.append(le16: 0)
            central.append(le32: UInt32(0o100600) << 16)  // a regular file, readable by its owner only
            central.append(le32: offset); central.append(name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32: 0x0605_4b50); out.append(le16: 0); out.append(le16: 0)
        out.append(le16: UInt16(entries.count)); out.append(le16: UInt16(entries.count))
        out.append(le32: UInt32(central.count)); out.append(le32: centralOffset); out.append(le16: 0)
        return out
    }

    // MARK: Reading

    /// Every file in the archive (folders and macOS's "__MACOSX" resource forks left out), from its central directory.
    static func read(_ data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { at + 2 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 : 0 }
        func u32(_ at: Int) -> Int { at + 4 <= bytes.count ? u16(at) | u16(at + 2) << 16 : 0 }
        // The end record sits in the last 64 KB (its comment can be up to 65,535 bytes).
        let floor = max(0, bytes.count - 22 - 65_535)
        guard let end = stride(from: bytes.count - 22, through: floor, by: -1).first(where: { u32($0) == 0x0605_4b50 }) else {
            throw Failure(errorDescription: "This isn’t a ZIP archive, or it’s damaged.")
        }
        let count = u16(end + 10), directory = u32(end + 16)
        guard count <= maxEntries else { throw Failure(errorDescription: "This archive holds too many files to be a browser export.") }
        var entries: [Entry] = []
        var at = directory
        for _ in 0..<count {
            guard u32(at) == 0x0201_4b50 else { throw Failure(errorDescription: "The archive’s file list is damaged.") }
            let flags = u16(at + 8), method = u16(at + 10), packed = u32(at + 20), size = u32(at + 24)
            let nameLength = u16(at + 28), extra = u16(at + 30), comment = u16(at + 32), local = u32(at + 42)
            guard at + 46 + nameLength <= bytes.count else { throw Failure(errorDescription: "The archive’s file list is damaged.") }
            let name = String(decoding: bytes[(at + 46)..<(at + 46 + nameLength)], as: UTF8.self)
            at += 46 + nameLength + extra + comment
            guard !name.hasSuffix("/"), !name.hasPrefix("__MACOSX/"), !(name as NSString).lastPathComponent.hasPrefix("._") else { continue }
            guard flags & 1 == 0 else { throw Failure(errorDescription: "“\(name)” is encrypted; export it again without a password.") }
            guard size <= maxEntrySize, packed <= maxEntrySize else { throw Failure(errorDescription: "“\(name)” is too large to import.") }
            guard u32(local) == 0x0403_4b50 else { throw Failure(errorDescription: "The archive’s data for “\(name)” is damaged.") }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + packed <= bytes.count else { throw Failure(errorDescription: "The archive is cut short.") }
            let raw = Data(bytes[start..<(start + packed)])
            switch method {
            case 0: entries.append(Entry(name: name, data: raw))
            case 8: entries.append(Entry(name: name, data: try inflate(raw, size: size)))
            default: throw Failure(errorDescription: "“\(name)” uses a compression Ikago can’t read.")
            }
        }
        return entries
    }

    /// Raw DEFLATE (what ZIP stores), which Apple's `COMPRESSION_ZLIB` decodes.
    private static func inflate(_ data: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { target in
            data.withUnsafeBytes { source in
                compression_decode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, size,
                                          source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw Failure(errorDescription: "A file in the archive couldn’t be decompressed.") }
        return output
    }

    // MARK: Helpers

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    private static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let time = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        let day = UInt16(max(0, (parts.year ?? 1980) - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
        return (time, day)
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
    mutating func append(le32 value: UInt32) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
}
