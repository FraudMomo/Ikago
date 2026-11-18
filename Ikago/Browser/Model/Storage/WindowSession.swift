import Foundation

/// A regular window after the first, saved inside the first window's session (`Session.windows`): its own tabs,
/// groups, split views and place on screen. Spaces, settings, history and bookmarks are the session's, shared by all.
struct WindowSession: Codable, Equatable {
    var tabs: [SavedTab] = []
    var active: String?
    var closed: [SavedTab]? = nil
    var splits: [[String]]? = nil
    var splitLayout: String? = nil
    var activeSpace: UUID? = nil
    var lastActiveTab: [String: String]? = nil
    var folders: [TabFolder]? = nil
    var sidebar: Bool? = nil
    /// x, y, width, height in screen coordinates.
    var frame: [Double]? = nil
    /// Closed windows only: when it closed (seconds since 1970), for ⌘⇧T's order.
    var closedAt: Double? = nil

    static let maxWindows = 20
    /// Recently closed windows ⌘⇧T can bring back, newest first.
    static let maxClosedWindows = 5

    var screenFrame: CGRect? {
        guard let frame, frame.count == 4, frame[2] >= 200, frame[3] >= 200 else { return nil }
        return CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])
    }

    /// Checked like a session's own tabs; a window that fails is skipped at launch rather than failing the session.
    func isValid(besides taken: Set<String>) -> Bool {
        var session = Session()
        session.tabs = tabs; session.active = active; session.closed = closed ?? []; session.folders = folders
        guard (try? session.validate()) != nil else { return false }
        return taken.isDisjoint(with: tabs.map(\.id))
    }
}
