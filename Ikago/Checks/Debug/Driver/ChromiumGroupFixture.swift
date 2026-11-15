#if DEBUG
import Foundation

/// Fixture writer follows Chromium's documented on-disk C structs and Pickle payloads.
struct ChromiumGroupFixture {
    var data = Data([0x53, 0x4e, 0x53, 0x53, 3, 0, 0, 0])
    static func u32(_ value: Int) -> Data {
        var number = UInt32(truncatingIfNeeded: value).littleEndian
        return withUnsafeBytes(of: &number) { Data($0) }
    }
    static func u64(_ value: UInt64) -> Data {
        var number = value.littleEndian
        return withUnsafeBytes(of: &number) { Data($0) }
    }
    mutating func command(_ id: UInt8, _ contents: Data) {
        var size = UInt16(contents.count + 1).littleEndian
        withUnsafeBytes(of: &size) { data.append(contentsOf: $0) }
        data.append(id); data.append(contents)
    }
    mutating func nav(_ id: Int, url: String, window: Int = 10, order: Int? = nil) {
        var body = Self.u32(id) + Self.u32(0) + Self.u32(url.utf8.count) + Data(url.utf8)
        while body.count % 4 != 0 { body.append(0) }
        body.append(Self.u32(0)) // Empty navigation title; use the URL as the visible title.
        command(6, Self.u32(body.count) + body)
        command(0, Self.u32(window) + Self.u32(id)) // Window ID precedes tab ID.
        command(2, Self.u32(id) + Self.u32(order ?? id))
    }
    mutating func member(_ tab: Int, group: UInt64?, abi32: Bool = false) {
        var body = Self.u32(tab)
        if !abi32 { body.append(Self.u32(0)) }
        body.append(Self.u64(group == nil ? 0 : 0x1122334455667788))
        body.append(Self.u64(group ?? 0))
        body.append(group == nil ? 0 : 1)
        while body.count < (abi32 ? 24 : 32) { body.append(0) }
        command(25, body)
    }
    mutating func metadata(_ group: UInt64, title: String, color: Int, collapsed: Bool? = false, legacy: Bool = false) {
        var body = Self.u64(0x1122334455667788) + Self.u64(group) + Self.u32(title.utf16.count)
        body.append(title.data(using: .utf16LittleEndian)!)
        while body.count % 4 != 0 { body.append(0) }
        body.append(Self.u32(color))
        if let collapsed { body.append(Self.u32(collapsed ? 1 : 0)) }
        // Saved GUID fields added by Chrome M113 follow the collapsed boolean.
        body.append(Self.u32(1)); body.append(Self.u32(4)); body.append(Data("guid".utf8))
        command(legacy ? 26 : 27, Self.u32(body.count) + body)
    }
    static func grouped() -> Data {
        var fixture = Self()
        fixture.metadata(1, title: "Old name", color: 1)
        for id in 1...10 {
            fixture.nav(id, url: id == 3 ? "https://groups.example/1" : "https://groups.example/\(id)", window: id == 7 ? 50 : 10)
        }
        fixture.member(1, group: 1); fixture.member(2, group: 1)
        fixture.member(3, group: 2); fixture.member(4, group: 3)
        fixture.member(5, group: 1); fixture.member(5, group: nil)
        fixture.member(6, group: 1); fixture.member(6, group: 2)
        fixture.member(7, group: 3); fixture.member(8, group: 1)
        fixture.member(9, group: 1); fixture.member(10, group: 4)
        fixture.command(12, Self.u32(9) + Data([1, 0, 0, 0]))
        fixture.command(16, Self.u32(8) + Data(repeating: 0, count: 12))
        fixture.command(17, Self.u32(50) + Data(repeating: 0, count: 12))
        fixture.metadata(1, title: "Research 🧭", color: 6, collapsed: true)
        fixture.metadata(2, title: "Research 🧭", color: 8)
        fixture.metadata(3, title: "", color: 99)
        fixture.metadata(5, title: "Closed group", color: 2) // No live members.
        return fixture.data
    }
}
#endif
