#if DEBUG
import Foundation

/// Safari extensions are found without a button: an app with one appears while Settings is open, a nested folder
/// (Utilities, Setapp) counts, other app extensions don't, and a deleted app disappears.
@MainActor
enum SafariExtensionScanChecks {
    static func run() async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            if !value { failures += 1 }
            print("IKTEST safariscan \(value ? "PASS" : "FAIL") \(title)")
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "ikago-safari-scan-\(UUID().uuidString)")
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func makeApp(_ path: String, extension name: String, point: String) {
            let contents = root.appending(path: path).appending(path: "Contents/PlugIns/\(name).appex/Contents")
            try? fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let info: NSDictionary = ["CFBundleDisplayName": name, "NSExtension": ["NSExtensionPointIdentifier": point]]
            info.write(to: contents.appending(path: "Info.plist"), atomically: true)
        }
        let scanner = SafariExtensionScanner(roots: [root])
        scanner.start()
        try? await Task.sleep(for: .milliseconds(400))
        check(scanner.found.isEmpty, "an empty folder has none")
        // Written into place in one move, as an installer finishes.
        let staging = fm.temporaryDirectory.appending(path: "ikago-staging-\(UUID().uuidString)")
        let contents = staging.appending(path: "Contents/PlugIns/Shield Extension.appex/Contents")
        try? fm.createDirectory(at: contents, withIntermediateDirectories: true)
        (["CFBundleDisplayName": "Shield Extension", "NSExtension": ["NSExtensionPointIdentifier": "com.apple.Safari.web-extension"]] as NSDictionary)
            .write(to: contents.appending(path: "Info.plist"), atomically: true)
        try? fm.moveItem(at: staging, to: root.appending(path: "Shield.app"))
        for _ in 0..<40 where scanner.found.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        check(scanner.found.map(\.name) == ["Shield"], "a newly installed app's extension appears on its own (\(scanner.found.map(\.name)))")
        makeApp("Utilities/Tool.app", extension: "Tool", point: "com.apple.Safari.web-extension")
        makeApp("Widget.app", extension: "Widget", point: "com.apple.widgetkit-extension")
        for _ in 0..<40 where Set(scanner.found.map(\.name)) != ["Shield", "Tool"] { try? await Task.sleep(for: .milliseconds(100)) }
        check(Set(scanner.found.map(\.name)) == ["Shield", "Tool"], "apps one folder down count; other app extensions don't")
        makeApp("Speed.app", extension: "Speed", point: "com.apple.Safari.extension")
        for _ in 0..<40 where scanner.found.count < 3 { try? await Task.sleep(for: .milliseconds(100)) }
        check(scanner.found.last.map { $0.name == "Speed" && $0.kind == .safariOnly } == true,
              "a Safari app extension is listed, marked Safari only, after the ones Ikago runs")
        try? fm.removeItem(at: root.appending(path: "Speed.app"))
        try? fm.removeItem(at: root.appending(path: "Shield.app"))
        for _ in 0..<40 where scanner.found.map(\.name) != ["Tool"] { try? await Task.sleep(for: .milliseconds(100)) }
        check(scanner.found.map(\.name) == ["Tool"], "a deleted app's extension disappears")
        print("IKTEST safariscanchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
