import Foundation

enum AppIdentity {
    static let bundleID = "app.ikago.browser"
    /// Ikago Test (`scripts/install_test.sh`): a copy beside the installed Ikago that shares its data, so only one of
    /// them runs at a time, and it never updates itself.
    static let isTestBuild = Bundle.main.object(forInfoDictionaryKey: "IkagoTestBuild") as? Bool == true
    /// Where sessions, extensions, favicons and Chromium profiles live: the protected container when
    /// this build is signed for it, otherwise Application Support.
    static var dataDirectory: URL {
        ProtectedStorage.container?.appending(path: "Ikago", directoryHint: .isDirectory)
            ?? supportDirectory(home: FileManager.default.homeDirectoryForCurrentUser)
    }
    /// The updater runs outside Ikago and can't enter the container, so its folder stays here. It holds
    /// only the staged app and its status, no browsing data.
    static var updatesDirectory: URL {
        supportDirectory(home: FileManager.default.homeDirectoryForCurrentUser).appending(path: "Updates", directoryHint: .isDirectory)
    }

    static func supportDirectory(home: URL) -> URL {
        home.appending(path: "Library/Application Support/Ikago", directoryHint: .isDirectory)
    }
}
