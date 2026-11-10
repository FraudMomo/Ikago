import Foundation

/// A Space: its own tabs, pinned tabs, folders and theme. An isolated Space also gets its
/// own WebKit data store (separate logins and cookies, see WebProfiles).
struct SpaceProfile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var symbol: String
    /// Isolated Spaces use their own data store; shared ones use the Default profile.
    var isolated: Bool
    /// Window color in light and dark mode; nil uses the standard color.
    var colors: SpaceColors?
    /// Pre-color-picker sessions stored a theme name; read once to seed `colors`.
    var theme: String?

    var resolvedColors: SpaceColors { colors ?? SpaceColors.legacy(theme) ?? .standard }

    /// Profile ID handed to WebProfiles: "Default" or the Space's UUID string.
    var profileID: String { isolated ? id.uuidString : "Default" }

    static let defaultSpace = SpaceProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Personal",
        symbol: "house",
        isolated: false
    )

    /// Symbols offered when creating a Space.
    static let symbols = ["house", "briefcase", "book", "graduationcap", "hammer", "paintbrush",
                          "gamecontroller", "heart", "leaf", "airplane", "cart", "star"]
}

/// A collapsible group of tabs in one Space's sidebar.
struct TabFolder: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var spaceID: UUID
    var isOpen = true
    /// Label color (a `FolderTag` name); nil is plain.
    var tag: String? = nil
    /// Closed in a top layout ("Close Group"): it takes no strip space and its pages unload,
    /// until reopened. Optional so older sessions restore; the sidebar still lists it.
    var isClosed: Bool? = nil
    /// The group's icon: an SF Symbol name or an emoji. Nil is a folder in the group's color.
    var icon: String? = nil
}

/// Colors a folder can be labeled with, like tags.
enum FolderTag: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, teal, blue, purple, pink, gray
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}
