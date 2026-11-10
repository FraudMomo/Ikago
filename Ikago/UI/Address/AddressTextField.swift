import AppKit
import SwiftUI

/// The address/search input used everywhere (floating command bar, top-bar tab, sidebar).
/// AppKit underneath so focus is explicit: it takes the keyboard from the page when it
/// appears, selects its text, and handles ↑ ↓ Return and Esc itself.
struct AddressTextField: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var weight: NSFont.Weight = .regular
    var alignment: NSTextAlignment = .left
    var placeholder = "Search or enter address"
    let onSubmit: () -> Void
    let onMove: (Int) -> Void
    let onCancel: () -> Void
    var onComplete: (() -> Void)? = nil
    /// Omnibox presentation: an inline completion shown selected after `text`, or a highlighted
    /// row's temporary text. Edits go to `onEdit` (which decides whether inline completion may follow).
    var completion = ""
    var temporary: String? = nil
    var onEdit: ((String) -> Void)? = nil
    var onBacktab: (() -> Void)? = nil
    /// Shift+Delete on a highlighted row; returns whether it was handled.
    var onRemove: (() -> Bool)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FocusingTextField {
        let field = FocusingTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: FocusingTextField, context: Context) {
        context.coordinator.parent = self
        // Each assignment invalidates the field's layout, so only change what actually changed.
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        if field.font != font { field.font = font }
        if field.alignment != alignment { field.alignment = alignment }
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
        let shown = temporary ?? text + completion
        guard field.stringValue != shown else { return }
        field.stringValue = shown
        if let editor = field.currentEditor() {
            let length = (shown as NSString).length
            editor.selectedRange = temporary == nil && !completion.isEmpty
                ? NSRange(location: (text as NSString).length, length: (completion as NSString).length)
                : NSRange(location: length, length: 0)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressTextField
        init(_ parent: AddressTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if let onEdit = parent.onEdit { onEdit(field.stringValue) } else { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel()
            case #selector(NSResponder.insertTab(_:)):
                guard let complete = parent.onComplete else { return false }
                complete()
            case #selector(NSResponder.insertBacktab(_:)):
                guard let back = parent.onBacktab else { return false }
                back()
            case #selector(NSResponder.deleteForward(_:)), #selector(NSResponder.deleteBackward(_:)):
                guard NSApp.currentEvent?.modifierFlags.contains(.shift) == true, parent.onRemove?() == true else { return false }
            default: return false
            }
            return true
        }
    }
}

/// Becomes first responder (and selects its text) as soon as it is in a window.
final class FocusingTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let editor = currentEditor() as? NSTextView {
            editor.drawsBackground = false
            editor.backgroundColor = .clear
            editor.focusRingType = .none
        }
        return accepted
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window else { return }
            window.makeFirstResponder(self)
            self.currentEditor()?.selectAll(nil)
        }
    }
}

extension NSView {
    /// Depth-first search for a subview of the given type.
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        for child in subviews {
            if let match = child as? T { return match }
            if let match = child.firstDescendant(of: type) { return match }
        }
        return nil
    }
}
