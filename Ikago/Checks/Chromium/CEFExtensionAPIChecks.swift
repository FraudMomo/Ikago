import AppKit
import IKCEFBridge

@MainActor
enum CEFExtensionAPIChecks {
    static func writeFixture(in directory: URL) throws {
        let worker = """
        chrome.runtime.onMessage.addListener((message, sender, reply) => {
          if (message === 'ikago-popup-fixture') {
            (async () => {
              const stage=value=>chrome.tabs.sendMessage(sender.tab.id,{ikagoPopupStage:value}).catch(()=>{});
              stage('removing-storage');
              await chrome.storage.local.remove('fixturePopup');
              stage('focusing-window');
              await chrome.windows.update(sender.tab.windowId, {focused:true});
              await new Promise(r=>setTimeout(r,100));
              stage('opening-popup');
              await chrome.action.openPopup({windowId:sender.tab.windowId});
              stage('reading-popup-storage');
              for(let i=0;i<80;i++) {
                const data=await chrome.storage.local.get('fixturePopup');
                if(data.fixturePopup===sender.tab.id)return {opened:true,tab:data.fixturePopup};
                await new Promise(r=>setTimeout(r,25));
              }
              throw Error('Native action popup did not report its active tab');
            })().then(reply,e=>reply({error:e.message}));
            return true;
          }
          if (message !== 'ikago-api-fixture') return;
          (async () => {
            const id = sender.tab?.id;
            if (!Number.isInteger(id)) throw Error('No sender tab identifier');
            const tab = await chrome.tabs.get(id);
            const tabs = await chrome.tabs.query({});
            await chrome.scripting.executeScript({target:{tabId:id}, world:'ISOLATED',
              func:() => {document.documentElement.dataset.ikagoExtensionInjected='yes';}});
            return {id, url:tab.url, listed:tabs.some(t=>t.id===id)};
          })().then(reply, e=>reply({error:e.message}));
          return true;
        });
        """
        try Data(worker.utf8).write(to: directory.appending(path: "background.js"))
        try Data("<!doctype html><title>Ikago Fixture Popup</title><p>Native action popup</p><script src='popup.js'></script>".utf8)
            .write(to: directory.appending(path: "popup.html"))
        try Data("chrome.tabs.query({active:true,currentWindow:true}).then(tabs=>chrome.storage.local.set({fixturePopup:tabs[0]?.id}));setTimeout(()=>window.close(),1500);".utf8)
            .write(to: directory.appending(path: "popup.js"))
        let content = """
        chrome.runtime.sendMessage('ikago-api-fixture', response => {
          const error = chrome.runtime.lastError?.message || response?.error;
          document.documentElement.dataset.ikagoExtensionAPI = JSON.stringify(error ? {error} : response);
        });
        document.addEventListener('ikago-fixture-open-popup',()=>{
          chrome.runtime.sendMessage('ikago-popup-fixture', response=>{
            document.documentElement.dataset.ikagoExtensionPopup=JSON.stringify(response || {error:chrome.runtime.lastError?.message});
          });
        });
        chrome.runtime.onMessage.addListener(message=>{
          if(message.ikagoPopupStage)document.documentElement.dataset.ikagoPopupStage=message.ikagoPopupStage;
        });
        """
        let file = directory.appending(path: "content.js")
        var data = try Data(contentsOf: file)
        data.append(Data(content.utf8))
        try data.write(to: file)
    }
    static func run(_ page: IKCEFPage, profile: String, url: String) async throws {
        try await check(page, url: url, mustBeListed: false)
        _ = try IKCEFNativeTools.openPage(URL(string: url)!, profile: profile)
        var native: IKCEFPage?
        for _ in 0..<150 {
            for item in IKCEFNativeTools.windows() where item["url"] as? String == url {
                if let id = item["id"] as? Int { native = IKCEFNativeTools.hiddenPage(forWindow: id) }
            }
            if native != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let native else { throw CEFError.script("Native extension API control window was not created.") }
        try await check(native, url: url, mustBeListed: true)
    }
    private static func check(_ page: IKCEFPage, url: String, mustBeListed: Bool) async throws {
        for _ in 0..<150 {
            let result = try? await CEFSmoke.method(page, "Runtime.evaluate", [
                "expression": "({api:document.documentElement.dataset.ikagoExtensionAPI, injected:document.documentElement.dataset.ikagoExtensionInjected})", "returnByValue": true])
            if let value = (result?["result"] as? [String: Any])?["value"] as? [String: Any],
               let encoded = value["api"] as? String,
               let data = encoded.data(using: .utf8), let api = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("CEF_EXTENSION_API_RESULT \(api) injected=\(value["injected"] ?? "missing")")
                // This binary reports a Chrome extension tabId distinct from
                // CefBrowser.GetIdentifier(). Validate real target identity by
                // tabs.get's URL and injection into this same document instead.
                guard api["error"] == nil, (api["id"] as? Int ?? 0) > 0, api["url"] as? String == url,
                      value["injected"] as? String == "yes", !mustBeListed || api["listed"] as? Bool == true else {
                    throw CEFError.script("Extension background messaging, tab API or scripting did not work in an embedded page.")
                }
                print("CEF_EXTENSION_API_OK nativeChrome=\(mustBeListed) tabsQueryListed=\(api["listed"] ?? false) service-worker messaging tab-identity tabs-get isolated-scripting")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CEFError.script("Extension background API fixture timed out.")
    }
}
