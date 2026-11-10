#if DEBUG
import WebKit

@MainActor
enum ExtensionStorageChecks {
    static func run(_ browser: BrowserWindowController, phase: String = "cycle") async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST extensionstorage \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let manager = ExtensionManager.shared, initial = browser.state.snapshot()
        let id = "ssssssssssssssssssssssssssssssss"
        let folder = SessionStore.testDirectory.appending(path: "StorageFixture-\(UUID())")
        defer { if phase != "write" { manager.remove(id) }; browser.state.apply(initial) }
        do {
            if phase != "read" {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("{\"manifest_version\":3,\"name\":\"Storage fixture\",\"version\":\"1.0\",\"permissions\":[\"storage\"],\"options_ui\":{\"page\":\"page.html\"}}".utf8).write(to: folder.appending(path: "manifest.json"))
            try Data("<!doctype html><title>Storage fixture</title>".utf8).write(to: folder.appending(path: "page.html"))
            _ = try await manager.install(unpackedAt: folder, id: id, fromWebStore: false, approve: false)
            }
            let origin = manager.contexts[id]!.baseURL
            let tab = browser.openTabForExtension(url: "chrome-extension://\(id)/page.html", active: true, pinned: false)!
            try? await Task.sleep(for: .seconds(1))
            let script = """
                localStorage.setItem('ikago-test','kept');
                await chrome.storage.local.set({ikagoTest: 'kept'});
                await new Promise((resolve,reject) => {
                    const r = indexedDB.open('ikago-test',1);
                    r.onupgradeneeded=()=>r.result.createObjectStore('values');
                    r.onerror=()=>reject(r.error.message);
                    r.onsuccess=()=>{ const db=r.result,t=db.transaction('values','readwrite');
                        t.objectStore('values').put('kept','test');
                        t.oncomplete=()=>{db.close();resolve(true)}; t.onerror=()=>reject(t.error.message); };
                }); return true;
                """
            if phase != "read" {
            _ = try await tab.page!.webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
            try Data(origin.absoluteString.utf8).write(to: SessionStore.testDirectory.appending(path: "storage-origin.txt"))
            if phase == "write" {
                try? await Task.sleep(for: .seconds(1))
                print("IKTEST extensionstoragewrite PASS")
                return
            }
            // Leave the old page before unloading its origin and rebuilding the context.
            tab.load("about:blank")
            await manager.setEnabled(id, false)
            await manager.setEnabled(id, true)
            check(manager.contexts[id]?.baseURL == origin, "resource origin survives extension context recreation")
            tab.load("chrome-extension://\(id)/page.html")
            try? await Task.sleep(for: .seconds(1))
            } else {
                let saved = try String(contentsOf: SessionStore.testDirectory.appending(path: "storage-origin.txt"), encoding: .utf8)
                check(origin.absoluteString == saved, "resource origin survives a full browser restart")
            }
            let read = """
                const extensionStorage=await chrome.storage.local.get('ikagoTest');
                const indexed=await new Promise((resolve,reject)=>{
                    const r=indexedDB.open('ikago-test',1);
                    r.onupgradeneeded=()=>r.result.createObjectStore('values');
                    r.onerror=()=>reject(r.error.message);
                    r.onsuccess=()=>{const db=r.result,t=db.transaction('values');const q=t.objectStore('values').get('test');
                        q.onsuccess=()=>resolve(q.result||null); t.oncomplete=()=>db.close();};
                }); return {local:localStorage.getItem('ikago-test'),indexed,extension:extensionStorage.ikagoTest||null};
                """
            let result = try await tab.page!.webView.callAsyncJavaScript(read, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
            check(result?["local"] as? String == "kept", "localStorage survives context recreation")
            check(result?["indexed"] as? String == "kept", "IndexedDB survives context recreation")
            if WebProfiles.persistenceTestIdentifier != nil {
                check(result?["extension"] as? String == "kept", "persistent extension storage.local survives context recreation or restart")
            }
        } catch { check(false, error.localizedDescription) }
        print("IKTEST extensionstoragechecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
