#if DEBUG
import AppKit

/// Phishing warnings, HTTPS by default and the download prompt.
@MainActor
enum SafetyChecks {
    /// On its own, so the same checks can run with either engine driving the pages.
    static func runAlone(_ browser: BrowserWindowController) async {
        var failures = 0
        await run(browser) { value, message in
            print("IKTEST safety \(value ? "PASS" : "FAIL") \(message)")
            if !value { failures += 1 }
        }
        print("IKTEST safetychecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    static func run(_ browser: BrowserWindowController, check: (Bool, String) -> Void) async {
        func imitates(_ host: String, known: Set<String> = []) -> String? { SiteSafetyRules.imitatedSite(host: host, known: known)?.domain }
        // Imitations.
        check(imitates("paypa1.com") == "paypal.com" && imitates("rnicrosoft.com") == "microsoft.com", "swapped look-alike characters warn")
        check(imitates("gooogle.com") == "google.com" && imitates("amazom.com") == "amazon.com", "one-character typos of famous sites warn")
        check(imitates("paypal.com.secure-login.net") == "paypal.com" && imitates("www-paypal.com") == "paypal.com", "a famous address inside a longer one warns")
        check(imitates("paypal-login.com") == "paypal.com" && imitates("secure-coinbase-verify.net") == "coinbase.com", "a famous name plus login words warns")
        check(imitates("paypal.tk") == "paypal.com", "a famous name on an abused ending warns")
        check(imitates("xn--80ak6aa92e.com") == "apple.com", "a Cyrillic disguise (аррӏе.com) warns")
        check(Punycode.decode("80ak6aa92e") == "аррӏе" && Punycode.decode("bcher-kva") == "bücher", "Punycode decodes correctly")
        check(imitates("xn--pypal-4ve.com") != nil, "mixed alphabets warn")
        check(imitates("gardenshop.example", known: ["mybank.example"]) == nil && imitates("mybankk.example", known: ["mybank.example"]) == "mybank.example", "sites you use are protected too")
        // Things that must stay quiet.
        for host in ["www.google.com", "accounts.google.com", "google.se", "paypal.com", "github.com", "gist.github.com", "bücher.de", "xn--bcher-kva.de",
                     "example.com", "news.ycombinator.com", "apple-tv-reviews.org", "stackoverflow.com", "my-project.vercel.app", "192.168.1.1", "ample.com", "chase.com"] {
            check(imitates(host) == nil, "no false alarm on \(host)")
        }
        // The downloaded lists.
        let threats = ThreatHosts.shared
        check(ThreatHosts.parse(Data("evil-site.example\n# comment\n<html>\nnodots\nbad.example\n".utf8)).count == 2, "junk in a list is ignored")
        threats.useForTesting(["listed-phish.example", "paypal.com"])
        check(threats.contains("listed-phish.example") && threats.contains("login.listed-phish.example"), "listed hosts and their subdomains match")
        check(!threats.contains("example.com") && !threats.contains("paypal.com"), "a list entry can't flag a famous site")

        // A real navigation on the running engine is stopped before any request, then can be continued.
        let state = browser.state
        check(state.browserPreferences.forceHTTPS == true, "Always require HTTPS is on by default")
        var legacy = BrowserPreferences(); legacy.forceHTTPS = false; legacy.httpsDefaultApplied = nil
        check(legacy.validated.forceHTTPS == true, "older sessions get HTTPS by default once")
        var chosen = legacy.validated; chosen.forceHTTPS = false
        check(chosen.validated.forceHTTPS == false, "after that, turning it off is respected")
        state.newTab(url: "about:blank")
        try? await Task.sleep(for: .milliseconds(800))
        browser.open("https://listed-phish.example/", inNewTab: false)
        try? await Task.sleep(for: .milliseconds(800))
        check(state.activeTab?.loadError?.contains("phishing") == true, "\(BrowserRuntime.engine.title): a listed site shows the warning instead of loading")
        SiteSafety.allow("listed-phish.example", state: state)
        check(SiteSafety.warning(for: URL(string: "https://listed-phish.example/")!, state: state) == nil, "Continue Anyway is remembered for that site")
        state.browserPreferences.siteSafetyExceptions = nil
        var off = state.browserPreferences; off.fraudulentWebsiteWarning = false
        let saved = state.browserPreferences; state.browserPreferences = off
        check(SiteSafety.warning(for: URL(string: "https://listed-phish.example/")!, state: state) == nil, "the setting turns warnings off")
        state.browserPreferences = saved
        threats.useForTesting([])

        // The download prompt.
        let downloads = DownloadPermissions.shared
        let page = URL(string: "https://files.example/"), file = URL(string: "https://cdn.example/a.zip")
        check(DownloadPermissions.site(pageURL: page, downloadURL: file) == "files.example" && DownloadPermissions.site(pageURL: nil, downloadURL: file) == "cdn.example", "the asking site is the page, else the file's host")
        downloads.testAnswer = false
        let denied = await downloads.mayDownload(pageURL: page, downloadURL: file, state: state, window: nil)
        let before = downloads.testPrompts
        let nagged = await downloads.mayDownload(pageURL: page, downloadURL: file, state: state, window: nil)
        check(!denied && !nagged && downloads.testPrompts == before, "a declined site can't ask again straight away")
        downloads.forgetDeclines(); downloads.testAnswer = true
        let allowed = await downloads.mayDownload(pageURL: page, downloadURL: file, state: state, window: nil)
        let prompts = downloads.testPrompts
        let again = await downloads.mayDownload(pageURL: page, downloadURL: file, state: state, window: nil)
        check(allowed && again && downloads.testPrompts == prompts && state.browserPreferences.downloadSites?.contains("files.example") == true, "an allowed site is remembered")
        state.browserPreferences.downloadSites = nil
        downloads.testAnswer = nil
    }
}
#endif
