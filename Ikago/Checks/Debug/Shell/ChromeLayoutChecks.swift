#if DEBUG
import Foundation

/// Saved toolbar layouts from before the six places read into the place nearest each old one, once, and the new places
/// round-trip.
@MainActor
enum ChromeLayoutChecks {
    static func run() {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST chromelayout \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        func decode(_ json: String) -> ChromeLayout? { try? JSONDecoder().decode(ChromeLayout.self, from: Data(json.utf8)) }

        let old = decode("""
        {"topLeading":["history"],"topCenter":["bookmarks"],"sidebarTop":["back","forward"],
         "bottomLeading":["settings"],"sidebarBottom":["spaces"],"bottomTrailing":["downloads"],
         "toolbarLeading":["back"],"toolbarNearLeading":["reload"],"toolbarNearTrailing":["share"],"toolbarTrailing":["notes"],
         "pageBarLeading":["forward"],"pageBarTrailing":["devices"],"addressShowsReload":false,"addressShowsSiteInfo":true,
         "rail":["sidebarToggle"],"sidebarShowsAddress":true,"sidebarShowsNewTab":false}
        """)
        check(old?.sidebarTop == [.history, .bookmarks, .back, .forward], "a top row's left, centre and right join in order")
        check(old?.sidebarBottom == [.settings, .spaces, .downloads], "a bottom row's left, centre and right join in order")
        check(old?.toolbarLeading == [.back, .reload] && old?.toolbarTrailing == [.share, .notes],
              "the places beside the address join the toolbar's sides")
        check(old?.address == [.siteInfo, .forward, .devices], "the bar above the page and the address switches move into the address field")
        check(old?.sidebarShowsNewTab == false && old?.rail == [.sidebarToggle], "the rest stays")
        check(decode("{}") == ChromeLayout(), "an empty layout is the default")
        if let old, let data = try? JSONEncoder().encode(old) {
            check(decode(String(decoding: data, as: UTF8.self)) == old, "the new places read back as saved")
        } else {
            check(false, "the new places read back as saved")
        }
        print("IKTEST chromelayoutchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
