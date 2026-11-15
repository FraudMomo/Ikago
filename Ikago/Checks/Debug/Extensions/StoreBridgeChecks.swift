#if DEBUG
import Foundation

/// Exercises the real store DOM script with deterministic compatibility replies on a local page.
@MainActor
enum StoreBridgeChecks {
    static func run(_ browser: BrowserWindowController) async {
        guard let page = browser.activeController?.page else { return }
        let script = WebStoreBridge.source
            .replacingOccurrences(of: "if (location.host !== 'chromewebstore.google.com') return", with: "if (false) return")
            .replacingOccurrences(of: "const bridge = window.webkit.messageHandlers.ikagoStore", with: """
                const bridge = {postMessage: async ({action,id}) => {
                  if (action === 'install') { globalThis.testInstalled = id; return {state: 'installed', reason: 'Added to Ikago'} }
                  return id === 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                    ? {state: 'unsupported', reason: 'Not supported in Ikago. Chrome themes cannot change browser appearance.'}
                    : id === 'cccccccccccccccccccccccccccccccc' ? {state: 'limited', reason: 'Limited support. Companion app unavailable.'} : {state: 'none', reason: 'No known incompatibility found.'}
                }}
                """)
        do {
            let result = try await page.callAsync("""
                const original = location.href
                const a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', c = 'cccccccccccccccccccccccccccccccc'
                history.replaceState(null, '', '/detail/fixture/' + a)
                document.body.innerHTML = '<main style="padding:48px;font:18px system-ui"><h1>Extension compatibility fixture</h1><button style="padding:12px;border:0;border-radius:20px"><span>Add to Chrome</span></button></main>'
                ;\(script);
                const wait = () => new Promise(resolve => setTimeout(resolve, 150))
                await wait()
                const button = document.querySelector('button')
                const unsupported = button.disabled && button.textContent === 'Not supported in Ikago'
                  && document.getElementById('ikago-compatibility').textContent.includes('Chrome themes')
                history.replaceState(null, '', '/detail/fixture/' + c)
                document.body.append(document.createElement('br'))
                await wait()
                const limited = !button.disabled && button.textContent === 'Add to Ikago (Limited)'
                history.replaceState(null, '', '/detail/fixture/' + b)
                document.body.append(document.createElement('br'))
                await wait()
                const allowed = !button.disabled && button.textContent === 'Add to Ikago'
                button.click()
                await wait()
                const installed = globalThis.testInstalled === b && button.textContent === 'Added to Ikago'
                history.replaceState(null, '', '/detail/fixture/' + a)
                document.body.append(document.createElement('br'))
                await wait()
                const navigation = button.disabled && button.textContent === 'Not supported in Ikago'
                history.replaceState(null, '', original)
                return {unsupported, limited, allowed, installed, navigation, pass: unsupported && limited && allowed && installed && navigation}
                """)
            print("IKTEST storebridgechecks \(result.map { "\($0)" } ?? "nil")")
        } catch { print("IKTEST storebridgechecks FAIL \((error as NSError).userInfo)") }
    }
}
#endif
