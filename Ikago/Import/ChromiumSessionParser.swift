import Foundation

/// SNSS session commands and Chromium Pickle strings. Only current HTTP(S) entries are imported.
enum ChromiumSessionParser {
    static func read(_ data: Data, groupNamespace: String = "") throws -> [ImportTab] {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, bytes.starts(with: Array("SNSS".utf8)) else { throw ImportFileParser.error("Not a Chromium session file.") }
        let version = integer(bytes, 4)
        guard version == 1 || version == 3 else { throw ImportFileParser.error("This Chromium session uses encrypted or unsupported session storage. Export the open tabs as JSON/bookmarks instead.") }
        var navigations: [Int: [Int: ImportTab]] = [:], selected: [Int: Int] = [:], order: [Int: Int] = [:], windows: [Int: Int] = [:]
        var pinned = Set<Int>(), closed = Set<Int>(), closedWindows = Set<Int>()
        var membership: [Int: String] = [:], groups: [String: GroupMetadata] = [:]
        var offset = 8
        while offset + 3 <= bytes.count {
            let size = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
            offset += 2
            guard size >= 1, offset + size <= bytes.count else { throw ImportFileParser.error("The session file is truncated. Close the source browser and try again.") }
            let command = bytes[offset]
            let payload = Array(bytes[(offset + 1)..<(offset + size)])
            offset += size
            if [25, 26, 27].contains(command), payload.count < 4 { throw malformedGroup() }
            guard payload.count >= 4 else { continue }
            let id = integer(payload, 0)
            switch command {
            case 0 where payload.count >= 8: windows[integer(payload, 4)] = id
            case 2 where payload.count >= 8: order[id] = integer(payload, 4)
            case 7 where payload.count >= 8: selected[id] = integer(payload, 4)
            case 12 where payload.count >= 5:
                if payload[4] != 0 { pinned.insert(id) } else { pinned.remove(id) }
            case 16: closed.insert(id)
            case 17: closedWindows.insert(id)
            case 25:
                // Chromium serializes a C struct: int32 tab, padding, two uint64s, bool, padding.
                // 64-bit macOS/Windows/Linux use 32 bytes; 32-bit sessions use 24 bytes.
                let tokenOffset: Int, flagOffset: Int
                switch payload.count {
                case 32: tokenOffset = 8; flagOffset = 24
                case 24: tokenOffset = 4; flagOffset = 20
                default: throw ImportFileParser.error("The session contains an unsupported tab-group record.")
                }
                if payload[flagOffset] != 0 {
                    guard let token = token(payload, at: tokenOffset) else { throw malformedGroup() }
                    membership[id] = token
                } else { membership[id] = nil }
            case 26, 27:
                let metadata = try groupMetadata(payload, legacy: command == 26)
                groups[metadata.token] = metadata.value
            case 6:
                // The command contains a Pickle header, tab ID, navigation index, URL, UTF-16 title.
                guard payload.count >= 16 else { continue }
                var cursor = 4
                let tabID = integer(payload, cursor); cursor += 4
                let index = integer(payload, cursor); cursor += 4
                guard let urlBytes = string(payload, cursor: &cursor, utf16: false), let url = String(bytes: urlBytes, encoding: .utf8), AddressResolver.isWebURL(url) else { continue }
                let titleBytes = string(payload, cursor: &cursor, utf16: true) ?? []
                let title = String(data: Data(titleBytes), encoding: .utf16LittleEndian) ?? url
                navigations[tabID, default: [:]][index] = ImportTab(url: url, title: String(title.prefix(512)))
            default: break
            }
        }
        guard offset == bytes.count else { throw ImportFileParser.error("The session file is truncated. Close the source browser and try again.") }
        return navigations.keys.sorted {
            let left = (windows[$0] ?? 0, order[$0] ?? $0), right = (windows[$1] ?? 0, order[$1] ?? $1)
            return left == right ? $0 < $1 : left < right
        }.compactMap { id in
            guard !closed.contains(id), !closedWindows.contains(windows[id] ?? -1), let entries = navigations[id],
                  var tab = entries[selected[id] ?? -1] ?? entries[entries.keys.max() ?? -1] else { return nil }
            tab.pinned = pinned.contains(id)
            if !tab.pinned, let token = membership[id] {
                let metadata = groups[token]
                tab.group = metadata?.title.isEmpty == false ? metadata?.title : "Imported Group"
                tab.groupID = "chromium:\(groupNamespace):\(token)"
                tab.groupColor = metadata?.color ?? "gray"
                tab.groupCollapsed = metadata?.collapsed ?? false
            }
            return tab
        }
    }

    private struct GroupMetadata {
        var title: String
        var color: String
        var collapsed: Bool
    }

    // Chromium's format: session_service_commands.cc and base/token.cc.
    // https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/sessions/core/session_service_commands.cc
    private static func groupMetadata(_ payload: [UInt8], legacy: Bool) throws -> (token: String, value: GroupMetadata) {
        guard payload.count >= 28, integer(payload, 0) == payload.count - 4,
              let token = token(payload, at: 4) else { throw malformedGroup() }
        var cursor = 20
        guard let titleBytes = string(payload, cursor: &cursor, utf16: true),
              let title = String(data: Data(titleBytes), encoding: .utf16LittleEndian), cursor + 4 <= payload.count else { throw malformedGroup() }
        let colors = ["gray", "blue", "red", "yellow", "green", "pink", "purple", "teal", "orange"]
        let color = integer(payload, cursor); cursor += 4
        let tag = !legacy && colors.indices.contains(color) ? colors[color] : "gray"
        // The optional Pickle bool occupies four bytes; older records have no collapsed field.
        let collapsed = !legacy && cursor + 4 <= payload.count && integer(payload, cursor) != 0
        return (token, GroupMetadata(title: String(title.prefix(64)), color: tag, collapsed: collapsed))
    }

    private static func token(_ bytes: [UInt8], at offset: Int) -> String? {
        guard offset >= 0, offset + 16 <= bytes.count else { return nil }
        let value = bytes[offset..<(offset + 16)]
        guard value.contains(where: { $0 != 0 }) else { return nil }
        return value.map { String(format: "%02x", $0) }.joined()
    }
    private static func malformedGroup() -> NSError { ImportFileParser.error("The session contains a damaged tab-group record. Close the source browser and try again.") }

    private static func integer(_ bytes: [UInt8], _ offset: Int) -> Int {
        guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
        let raw = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        return Int(Int32(bitPattern: raw))
    }

    private static func string(_ bytes: [UInt8], cursor: inout Int, utf16: Bool) -> [UInt8]? {
        guard cursor + 4 <= bytes.count else { return nil }
        let units = integer(bytes, cursor); cursor += 4
        guard units >= 0, units <= 1_000_000 else { return nil }
        let count = units * (utf16 ? 2 : 1)
        guard cursor + count <= bytes.count else { return nil }
        let result = Array(bytes[cursor..<(cursor + count)])
        cursor += (count + 3) & ~3
        return result
    }
}
