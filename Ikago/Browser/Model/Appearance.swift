import Foundation

/// Three independent browser presentations.
enum TabLayout: String, Codable, CaseIterable, Identifiable {
    case vertical, horizontal
    var id: String { rawValue }
    var name: String {
        switch self { case .vertical: "Sidebar"; case .horizontal: "Top Bar" }
    }
    var usesTopTabs: Bool { self != .vertical }
}

enum TopTabStyle: String, CaseIterable, Identifiable {
    case separate, compact
    var id: String { rawValue }
    var name: String { self == .separate ? "Separate" : "Compact" }
}

/// The group label treatment shared by sidebar and top bar.
enum GroupLabelStyle: String, CaseIterable, Identifiable {
    case minimal, colorPill
    var id: String { rawValue }
    var name: String { self == .minimal ? "Minimal" : "Color pill" }
    var detail: String { self == .minimal ? "A small color marker." : "A softly colored background." }
}

/// How you edit the address: in place or in a floating command bar.
enum AddressStyle: String, Codable, CaseIterable, Identifiable {
    case integrated, floating
    var id: String { rawValue }
    var name: String { self == .integrated ? "Integrated" : "Floating" }
}

/// What ⌘T opens.
enum NewTabMode: String, Codable, CaseIterable, Identifiable {
    case commandBar, homepage, extensionPage
    var id: String { rawValue }
    var name: String {
        switch self {
        case .commandBar: "Command bar"
        case .homepage: "Homepage"
        case .extensionPage: "Extension page"
        }
    }
}

/// Follow macOS, or force light or dark.
enum ColorMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

/// A Space's window color, one for light mode and one for dark mode (0xRRGGBB).
struct SpaceColors: Codable, Equatable, Hashable {
    var light: UInt32
    var dark: UInt32

    static let standard = presets[0].colors

    struct Preset: Identifiable {
        let name: String
        let colors: SpaceColors
        var id: String { name }
    }

    /// Space identity pairs that tint the full sidebar and top bar. The first is the standard; new Spaces take the next unused.
    static let presets: [Preset] = [
        Preset(name: "Graphite", colors: SpaceColors(light: 0xE8E8EA, dark: 0x1E1E20)),
        Preset(name: "Mist", colors: SpaceColors(light: 0xB9D9EB, dark: 0x204355)),
        Preset(name: "Sand", colors: SpaceColors(light: 0xEED4AD, dark: 0x51402A)),
        Preset(name: "Sage", colors: SpaceColors(light: 0xBFD8B9, dark: 0x294A37)),
        Preset(name: "Rose", colors: SpaceColors(light: 0xEABAC8, dark: 0x542F40)),
        Preset(name: "Lilac", colors: SpaceColors(light: 0xCEBFF0, dark: 0x40335F)),
        Preset(name: "Stone", colors: SpaceColors(light: 0xD9C8BA, dark: 0x4B3D35)),
    ]

    /// The first release's stronger presets (navy-ish in dark mode), mapped to the new ones.
    static func migrated(_ colors: SpaceColors) -> SpaceColors {
        let neutralPairs: [SpaceColors: String] = [
            SpaceColors(light: 0xDDE5E8, dark: 0x212528): "Mist", SpaceColors(light: 0xE9E3D8, dark: 0x262420): "Sand",
            SpaceColors(light: 0xDFE7DC, dark: 0x212522): "Sage", SpaceColors(light: 0xEEE0E2, dark: 0x272224): "Rose",
            SpaceColors(light: 0xE4E1EE, dark: 0x232229): "Lilac", SpaceColors(light: 0xE5E2DE, dark: 0x242321): "Stone"
        ]
        if let name = neutralPairs[colors], let preset = presets.first(where: { $0.name == name }) { return preset.colors }
        let old: [UInt32: String] = [0x1F2A30: "Mist", 0x2B2620: "Sand", 0x2F2226: "Rose", 0x1F2A22: "Sage",
                                     0x25223A: "Lilac", 0x1A2533: "Mist", 0x33241B: "Stone", 0x1C1E21: "Graphite"]
        guard let name = old[colors.dark] else { return colors }
        return presets.first { $0.name == name }?.colors ?? colors
    }

    /// Legacy theme names from older sessions.
    static func legacy(_ name: String?) -> SpaceColors? {
        let map = ["mist": "Mist", "sand": "Sand", "rose": "Rose", "graphite": "Graphite"]
        guard let name, let preset = map[name] else { return nil }
        return presets.first { $0.name == preset }?.colors
    }
}
