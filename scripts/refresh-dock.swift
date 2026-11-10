// Updates only Ikago's own Dock entries, keeping their position.
import AppKit

let identifier = "app.ikago.browser"
let destination = URL(fileURLWithPath: "/Applications/Ikago.app", isDirectory: true)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

if CommandLine.arguments.contains("--prepare") {
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
    for app in running where !app.terminate() { fail("Quit Ikago before installing.") }
    let deadline = Date().addingTimeInterval(15)
    while running.contains(where: { !$0.isTerminated }), Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard running.allSatisfy(\.isTerminated) else { fail("Ikago is still running. Installation stopped.") }
    print(running.isEmpty ? "stopped" : "running")
    exit(0)
}

guard let bundle = Bundle(url: destination), bundle.bundleIdentifier == identifier,
      let name = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
      let icon = bundle.url(forResource: name, withExtension: "icns"),
      NSImage(contentsOf: icon) != nil else { fail("Installed Ikago app or bundled icon is missing.") }

let domain = "com.apple.dock"
// Read and write only the app arrays; never replace the rest of the user's Dock preferences.
_ = CFPreferencesAppSynchronize(domain as CFString)
func refreshed(_ tiles: [[String: Any]]) -> ([[String: Any]], Bool) {
    var changed = false
    let result = tiles.map { tile -> [String: Any] in
        guard var data = tile["tile-data"] as? [String: Any] else { return tile }
        let file = data["file-data"] as? [String: Any]
        let path = (file?["_CFURLString"] as? String).flatMap(URL.init(string:))?.path
        guard data["bundle-identifier"] as? String == identifier || path == destination.path else { return tile }
        var updated = tile
        data["file-data"] = ["_CFURLString": destination.absoluteString, "_CFURLStringType": 15]
        data["file-label"] = "Ikago"
        data["bundle-identifier"] = identifier
        // A bookmark or cached modification date can otherwise resolve back to the old app.
        for key in ["book", "file-mod-date", "parent-mod-date"] { data.removeValue(forKey: key) }
        updated["tile-data"] = data
        changed = true
        return updated
    }
    return (result, changed)
}
for key in ["persistent-apps", "recent-apps"] {
    guard let tiles = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? [[String: Any]] else { continue }
    let (updated, changed) = refreshed(tiles)
    if changed { CFPreferencesSetAppValue(key as CFString, updated as CFArray, domain as CFString) }
}
guard CFPreferencesAppSynchronize(domain as CFString) else { fail("Could not save Ikago Dock entries.") }
NSWorkspace.shared.noteFileSystemChanged(destination.path)
print("Refreshed Ikago Dock registration")
