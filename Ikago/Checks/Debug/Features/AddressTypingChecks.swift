#if DEBUG
import AppKit

/// Typing into the real ⌘T / ⌘L field while its delayed focus passes run: the inline completion stays selected after
/// what was typed, so the next letter replaces it instead of landing after it ("youtube.comou").
@MainActor
enum AddressTypingChecks {
    static func run(_ c: BrowserWindowController) async {
        guard WebProfiles.isTestMode, let window = c.window, let root = window.contentView else { return }
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            if !value { failures += 1 }
            print("IKTEST addresstyping \(value ? "PASS" : "FAIL") \(title)")
        }
        func field() -> FocusingTextField? {
            var found: [FocusingTextField] = []
            func walk(_ view: NSView) {
                if let field = view as? FocusingTextField, !field.isHiddenOrHasHiddenAncestor { found.append(field) }
                view.subviews.forEach(walk)
            }
            walk(root)
            return found.last
        }
        let base = c.state.activeTab?.url ?? ""
        let host = URL(string: base)?.host ?? "127.0.0.1"
        for (index, newTab) in [true, false, true].enumerated() {
            c.showCommandPalette(newTab: newTab)
            var typed = ""
            var dropped = false
            // Letters ~70 ms apart from the moment the field appears, straight through the 0.05/0.25/0.4 s refocus passes.
            for letter in host.prefix(6) {
                try? await Task.sleep(for: .milliseconds(70))
                // Runs 1 and 2: the field lets go of the keyboard after two letters, as when SwiftUI swaps the field
                // during its transition; the app's own refocus pass (0.25 s / 0.4 s) has to bring it back.
                if index > 0, typed.count == 2, !dropped {
                    dropped = true
                    window.makeFirstResponder(nil)
                    try? await Task.sleep(for: .milliseconds(260))
                }
                guard let editor = field()?.currentEditor() as? NSTextView, window.firstResponder === editor else { continue }
                editor.insertText(String(letter), replacementRange: NSRange(location: NSNotFound, length: 0))
                typed.append(letter)
                // The suggestion list appearing after the first letter can move the field to a new parent in the same
                // window, which runs its "joined a window" focus again.
                if typed.count == 1 {
                    try? await Task.sleep(for: .milliseconds(40))
                    field()?.viewDidMoveToWindow()
                    try? await Task.sleep(for: .milliseconds(40))
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
            let editor = field()?.currentEditor() as? NSTextView
            let text = editor?.string ?? ""
            let selected = editor.map { ($0.string as NSString).substring(with: $0.selectedRange()) } ?? ""
            let typedPart = typed.lowercased()
            check(text.lowercased().hasPrefix(typedPart) || text.lowercased().contains("://" + typedPart),
                  "run \(index): the field keeps what was typed first (\(text))")
            check(c.palette.query.lowercased() == typedPart, "run \(index): the query is exactly the letters typed (\(c.palette.query))")
            check(selected.isEmpty || text.hasSuffix(selected), "run \(index): only the completion is selected (\(selected))")
            // The next letter replaces the completion rather than following it.
            if let editor {
                editor.insertText("Z", replacementRange: NSRange(location: NSNotFound, length: 0))
                check(c.palette.query.lowercased() == typedPart + "z", "run \(index): the next letter follows what was typed (\(c.palette.query))")
            }
            c.dismissCommandPalette()
            try? await Task.sleep(for: .milliseconds(300))
        }
        print("IKTEST addresstypingchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
