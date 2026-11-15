import Foundation
import AppKit

// MARK: - Memory safety
extension WebTab {
    /// Preserve drafts, changed form values and live embedded documents. Failed inspection always keeps the page.
    func canReleaseMemory() async -> Bool {
        if await hasNavigationHistory() { return false }
        return (try? await callAsync("""
            const safe = document => {
              if (document.querySelector('[contenteditable]:not([contenteditable="false" i])')) return false;
              for (const field of document.querySelectorAll('input, textarea, select')) {
                if (field.type === 'hidden' || field.type === 'submit' || field.type === 'button' || field.type === 'reset') continue;
                if (field.tagName === 'SELECT') {
                  const options = [...field.options], hasDefault = options.some(option => option.defaultSelected);
                  if (options.some((option, index) => option.selected !== (option.defaultSelected || (!field.multiple && !hasDefault && index === 0)))) return false;
                } else if (field.type === 'file') {
                  if (field.files?.length) return false;
                } else if (field.type === 'checkbox' || field.type === 'radio') {
                  if (field.checked !== field.defaultChecked) return false;
                } else if (field.value !== field.defaultValue) return false;
              }
              for (const frame of document.querySelectorAll('iframe, frame')) {
                try { if (!frame.contentDocument || !safe(frame.contentDocument)) return false; } catch { return false; }
              }
              return true;
            };
            return safe(document);
            """) as? Bool) == true
    }
}

// MARK: - Performance
extension CEFWebTab {
    var performanceProcessID: Int32? { page.rendererProcessID > 0 ? Int32(page.rendererProcessID) : nil }
}

extension WebKitTab {
    var performanceProcessID: Int32? {
        // SPI: WebKit has no public tab-to-renderer mapping. Used only by visible diagnostics and demand-driven tab previews.
        let selector = NSSelectorFromString("_webProcessIdentifier")
        guard webView.responds(to: selector), let implementation = webView.method(for: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Int32
        let pid = unsafeBitCast(implementation, to: Getter.self)(webView, selector)
        return pid > 0 ? pid : nil
    }
}
