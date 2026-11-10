#if DEBUG
import AppKit
import SwiftUI

/// Test-driver actions that run a check suite, seed a fixture, measure a probe or render Settings.
extension TestDriver {
    /// Returns false for an action this file doesn't know.
    static func performCheck(_ action: String, _ arg: String, _ c: BrowserWindowController) async -> Bool {
        let state = c.state
        switch action {
        case "reopenchecks": ReopenChecks.run(c)
        case "settingsshot":
            // settingsshot:<category>|<dark or light>|<file.png>[|<width>]: renders Settings to an image.
            let parts = arg.split(separator: "|").map(String.init)
            if parts.count >= 3, let category = SettingsCategory(rawValue: parts[0]) {
                let width = parts.count > 3 ? CGFloat(Double(parts[3]) ?? 1120) : 1120
                state.settingsCategory = category
                state.colorMode = parts[1] == "dark" ? .dark : .light
                let host = NSHostingView(rootView: InternalPageView(page: .settings, state: state).frame(width: width, height: 1400))
                host.frame = NSRect(x: 0, y: 0, width: width, height: 1400)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
                window.orderBack(nil)
                try? await Task.sleep(for: .milliseconds(1500))
                host.layoutSubtreeIfNeeded()
                if let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: image)
                    try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: parts[2]))
                    print("IKTEST settingsshot \(parts[2])")
                }
                window.orderOut(nil)
            }
        case "mediademo": await MediaIslandDemo.run(c)
        case "islandprobe": await GroupDisclosureProbe.shared.runIsland(c)
        case "mediafullscreenchecks": await MediaFullscreenChecks.run(c)
        case "downloadpopupchecks": await DownloadPopupChecks.run(c)
        case "downloadchecks": await DownloadChecks.run(c, base: arg)
        case "backgroundtabchecks": await BackgroundTabChecks.run(c, base: arg)
        case "extensionstoragechecks": await ExtensionStorageChecks.run(c, phase: arg.isEmpty ? "cycle" : arg)
        case "chromechecks": await ChromeExtensionChecks.run(c)
        case "importdemo":
            do { try OneClickImportChecks.fixture(home: SessionStore.testDirectory.appending(path: "ImportSources")) } catch { print("IKTEST importdemo FAIL \(error)") }
            await state.importer.refresh()
        case "importaccessdemo":
            do {
                let home = SessionStore.testDirectory.appending(path: "ImportSources")
                try OneClickImportChecks.fixture(home: home)
                let profile = home.appending(path: "Library/Application Support/Google/Chrome/Profile 2")
                for file in ["Bookmarks", "Cookies", "Sessions"] {
                    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: profile.appending(path: file).path)
                }
                await state.importer.refresh()
                if let source = state.importer.profiles.first(where: { $0.directory == profile }) {
                    await state.importer.importProfile(source, into: state)
                }
            } catch { print("IKTEST importaccessdemo FAIL \(error)") }
        case "importfirst":
            if let source = state.importer.profiles.first(where: { $0.browser == "Google Chrome" && $0.preferred }) {
                await state.importer.importProfile(source, into: state)
                print("IKTEST oneclick \(state.importer.result ?? "nil")")
            }
        case "groupdemo":
            do {
                let tabs = try ChromiumSessionParser.read(ChromiumGroupFixture.grouped(), groupNamespace: "Visual fixture")
                _ = await state.applyImport(BrowserImportData(tabs: tabs), selection: ImportSelection(), to: state.activeSpaceID)
            } catch { print("IKTEST groupdemo FAIL \(error)") }
        case "importchecks": await BrowserImportChecks.run(c)
        case "newtabfocuschecks": await NewTabFocusChecks.run(c, base: arg)
        case "bookmarkdemo": BookmarkBarChecks.seed(c)
        case "bookmarkbarchecks": await BookmarkBarChecks.run(c)
        case "chromegeometrychecks": await BrowserChromeGeometryChecks.run(c)
        case "topbarpolishchecks": await TopBarPolishChecks.run(c, base: arg)
        case "topbarlayoutchecks": await TopBarLayoutChecks.run(c)
        case "storebridgechecks": await StoreBridgeChecks.run(c)
        case "groupseed": GroupDisclosureProbe.seed(c, perGroup: Int(arg) ?? 8)
        case "groupprobe":  // <group number>[,<scroll fraction 0…1>]
            let p = arg.split(separator: ",").map(String.init)
            await GroupDisclosureProbe.shared.run(c, group: Int(p.first ?? "") ?? 1, scrollTo: p.count > 1 ? Double(p[1]) : nil)
        case "layoutdemo": LayoutChecks.seed(c)
        case "taboverflowchecks": await TabOverflowChecks.run(c)
        case "tabscroll": await TabOverflowChecks.scroll(c, to: Double(arg) ?? 0)
        case "sizingchecks": await LayoutChecks.run(c)
        case "layoutmetrics": LayoutChecks.dump(c)
        case "splitinteractionchecks":
            await SplitInteractionChecks.run(c)
            // Fixture cleanup restores the original layout; let its transition finish
            // before subsequent native-scroll geometry checks start.
            try? await Task.sleep(for: .milliseconds(500))
        case "tabanimationchecks": await TabAnimationChecks.run()
        case "toplayoutfeaturechecks": await TopLayoutFeatureChecks.run(c)
        case "securitychecks": await SecurityChecks.run(c, base: arg)
        case "applinkchecks": await ExternalLinkChecks.run(c, base: arg)
        case "privacychecks": await PrivacyChecks.run(c, base: arg)
        case "safetychecks": await SafetyChecks.runAlone(c)
        case "datapersistencechecks": await WebsiteDataPersistenceChecks.run(c, arg: arg)
        case "defaultbrowserchecks": await DefaultBrowserChecks.run()
        case "autocompletechecks": await AutocompleteChecks.run()
        case "tabplacementchecks": await TabPlacementChecks.run()
        case "middleclickchecks": await MiddleClickChecks.run(c, base: arg)
        case "passwordautofillchecks": await PasswordAutoFillChecks.run(c, base: arg)
        case "featurechecks": await BrowserFeatureChecks.run(c)
        case "faviconstabilitychecks": await FaviconStabilityChecks.run(c)
        case "sidebarinteractionchecks": await SidebarInteractionChecks.run(c)
        case "tabreorderingchecks": await TabReorderingChecks.run(c)
        case "essentialschecks": await EssentialsChecks.run(c)
        case "bookmarknavigationchecks": await BookmarkNavigationChecks.run(c)
        case "protectedaddresschecks":
            await ProtectedAddressChecks.run(c)
            // Let the restored layout dismiss outgoing chrome before another fixture records geometry.
            try? await Task.sleep(for: .milliseconds(500))
        default: return false
        }
        return true
    }
}
#endif
