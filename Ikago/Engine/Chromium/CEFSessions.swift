import AppKit
import CryptoKit
import IKCEFBridge

@MainActor
enum CEFSessions {
    static var overrideRoot: URL?
    static var root: URL { overrideRoot ?? SessionStore.standard.directory.appending(path: "Chromium", directoryHint: .isDirectory) }
    private static var profiles: Set<String> = []
    static func prepare(_ profile: String) throws {
        CEFProtection.apply(BrowserSecurity.shared.preferences)
        guard !profiles.contains(profile) else { return }
        try IKCEFContexts.prepareProfile(profile, root: root, ephemeral: WebProfiles.isPrivate(profile) || WebProfiles.isTestMode)
        profiles.insert(profile)
    }
    /// Where a persistent profile lives, matching `IKCEFContexts.prepareProfile`.
    static func directory(for profile: String) -> URL {
        root.appending(path: SHA256.hash(data: Data(profile.utf8)).map { String(format: "%02x", $0) }.joined(), directoryHint: .isDirectory)
    }
    static func forget(_ profile: String) {
        _ = IKCEFContexts.forgetEphemeralProfile(profile)
        profiles.remove(profile)
    }
    static func scheduleProfileRemoval(_ profile: String) {
        let key = "CEFProfilesToDelete"
        var pending = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        pending.insert(profile)
        UserDefaults.standard.set(Array(pending).sorted(), forKey: key)
    }
    static func clearScheduledData() throws {
        guard overrideRoot == nil else { return }
        let key = "CEFProfilesToDelete"
        let pending = UserDefaults.standard.stringArray(forKey: key) ?? []
        for profile in pending {
            let directory = directory(for: profile)
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            UserDefaults.standard.set((UserDefaults.standard.stringArray(forKey: key) ?? []).filter { $0 != profile }, forKey: key)
        }
    }
    static func flush(_ completion: @escaping @MainActor () -> Void) {
        guard !profiles.isEmpty else { completion(); return }
        let pending = CEFCookieFlush(profiles.count, completion)
        for profile in profiles {
            IKCEFContexts.flushProfile(profile) { _ in MainActor.assumeIsolated { pending.tick() } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { pending.finish() }
    }
}
@MainActor
enum BrowserRuntime {
    /// The default engine for this launch: new tabs and every site without a rule (`SiteEngines`) use it.
    static var engine = BrowserEngine.webkit
    /// The engines pages can use in this launch: always WebKit, and Chromium when the default or a site rule needed it
    /// at launch. Chromium can only start at launch, so a Chromium rule added later applies after a relaunch.
    static var running: Set<BrowserEngine> = [.webkit]
    static func runs(_ engine: BrowserEngine) -> Bool { running.contains(engine) }
    static var helperExecutable: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Frameworks/Ikago Helper.app/Contents/MacOS/Ikago Helper")
    }
    static func stopRunLoop() {
        if IKCEFRuntime.ready { IKCEFRuntime.quitMessageLoop(); return }
        NSApp.stop(nil)
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(event, atStart: true)
        }
    }
}

@MainActor
private final class CEFCookieFlush {
    private var remaining: Int
    private var completion: (@MainActor () -> Void)?
    init(_ count: Int, _ completion: @escaping @MainActor () -> Void) {
        remaining = count
        self.completion = completion
    }
    func tick() {
        remaining -= 1
        if remaining == 0 { finish() }
    }
    func finish() {
        let callback = completion
        completion = nil
        callback?()
    }
}
