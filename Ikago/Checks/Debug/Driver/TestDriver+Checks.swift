#if DEBUG
import AppKit
import SwiftUI

/// Test-driver actions that run a check suite, seed a fixture, measure a probe or render Settings.
extension TestDriver {
    /// Returns false for an action this file doesn't know.
    static func performCheck(_ action: String, _ arg: String, _ c: BrowserWindowController) async -> Bool {
        let state = c.state
        switch action {
        case "pinassistantchecks": await PinAssistantChecks.run(c)
        case "refinementchecks": await InteractionRefinementChecks.run(c, base: arg)
        case "sidebarvisibilitychecks": await SidebarVisibilityChecks.run(c)
        case "featurebatchchecks": await FeatureBatchChecks.run(c)
        case "nestedgroupchecks": NestedGroupChecks.run(c)
        case "reopenchecks": ReopenChecks.run(c)
        case "settingsshot":
            // settingsshot:<category>|<dark or light>|<file.png>[|<width>]: renders Settings to an image.
            let parts = arg.split(separator: "|").map(String.init)
            if parts.count >= 3, let category = SettingsCategory(rawValue: parts[0]) {
                let width = parts.count > 3 ? CGFloat(Double(parts[3]) ?? 1120) : 1120
                state.settingsCategory = category
                state.colorMode = parts[1] == "dark" ? .dark : .light
                await render(InternalPageView(page: .settings, state: state), size: NSSize(width: width, height: 1400), to: parts[2])
            }
        case "welcomeshot":
            // welcomeshot:<step 0…3>|<dark or light>|<file.png>: renders one step of the welcome page.
            let parts = arg.split(separator: "|").map(String.init)
            if parts.count >= 3, let index = Int(parts[0]), WelcomeStep.allCases.indices.contains(index) {
                state.colorMode = parts[1] == "dark" ? .dark : .light
                let page = WelcomePage(state: state, tabID: nil, initialStep: WelcomeStep.allCases[index])
                    .environment(\.colorScheme, state.palette.isDark ? .dark : .light)
                await render(page, size: NSSize(width: 900, height: 640), to: parts[2])
            }
        case "mediademo": await MediaIslandDemo.run(c)
        case "sidebarprobe": await SidebarToggleProbe.run(c)
        case "islandprobe": await GroupDisclosureProbe.shared.runIsland(c)
        case "mediafullscreenchecks": await MediaFullscreenChecks.run(c)
        case "mediadetectionchecks": await MediaDetectionChecks.run(c)
        case "performancechecks": await PerformanceChecks.run(c)
        case "resourcechecks": await TabMemoryChecks.run(c, base: arg)
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
        case "storebridgechecks": await StoreBridgeChecks.run(c)
        case "groupseed": GroupDisclosureProbe.seed(c, perGroup: Int(arg) ?? 8)
        case "groupprobe":  // <group number>[,<scroll fraction 0…1>]
            let p = arg.split(separator: ",").map(String.init)
            await GroupDisclosureProbe.shared.run(c, group: Int(p.first ?? "") ?? 1, scrollTo: p.count > 1 ? Double(p[1]) : nil)
        case "layoutdemo": LayoutChecks.seed(c)
        case "sizingchecks": await LayoutChecks.run(c)
        case "layoutmetrics": LayoutChecks.dump(c)
        case "splitinteractionchecks":
            await SplitInteractionChecks.run(c)
            // Fixture cleanup restores the original layout; let its transition finish
            // before subsequent native-scroll geometry checks start.
            try? await Task.sleep(for: .milliseconds(500))
        case "tabanimationchecks": await TabAnimationChecks.run()
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
        case "faviconappearancechecks": await FaviconAppearanceChecks.run(c)
        case "sidebarinteractionchecks": await SidebarInteractionChecks.run(c)
        case "windowchecks": await WindowChecks.run(c)
        case "pipchecks": await PictureInPictureChecks.run(c)
        case "historychecks": await HistoryChecks.run(c)
        case "selectionpeekchecks": await SelectionPeekChecks.run(c)
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
