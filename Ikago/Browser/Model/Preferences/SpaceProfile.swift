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
    /// Closed by the retired Top Bar's "Close Group": its pages stay unloaded until reopened (Tab ▸ Reopen Closed
    /// Group). Optional so older sessions restore; the sidebar still lists it.
    var isClosed: Bool? = nil
    /// The group's icon: an SF Symbol name or an emoji. Nil is a folder in the group's color.
    var icon: String? = nil
    /// The group this one sits inside (nested groups); nil, or a group that no longer exists, is top level.
    var parentID: String? = nil
    /// Where a top-level group sits: nil in the block above the tabs (above the New Tab line); "" first among the loose
    /// tabs; a tab's id right after that loose tab, as Chrome and Firefox place groups among tabs. Optional so older
    /// sessions restore into the block, as before.
    var afterTabID: String? = nil
}

/// Colors a folder can be labeled with, like tags.
enum FolderTag: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, teal, blue, purple, pink, gray
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}
