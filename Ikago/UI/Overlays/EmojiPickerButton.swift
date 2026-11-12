import AppKit
import SwiftUI

/// The macOS emoji picker inserts through a real text input client, never the page.
struct EmojiPickerButton: NSViewRepresentable {
    let onChoose: (String) -> Void

    func makeNSView(context: Context) -> EmojiPickerHost { EmojiPickerHost(onChoose: onChoose) }
    func updateNSView(_ view: EmojiPickerHost, context: Context) { view.onChoose = onChoose }
    static func dismantleNSView(_ view: EmojiPickerHost, coordinator: ()) { view.restoreFocus() }

    static func emoji(in text: String) -> String? {
        text.first(where: { character in
            character.unicodeScalars.contains { $0.properties.isEmoji && ($0.properties.isEmojiPresentation || $0.value > 0x238C) }
        }).map(String.init)
    }
}

@MainActor
final class EmojiPickerHost: NSView, NSTextFieldDelegate {
    var onChoose: (String) -> Void
    private let field = NSTextField(string: "")
    private let button = NSButton(title: "Use emoji", target: nil, action: nil)
    private weak var previousResponder: NSResponder?

    init(onChoose: @escaping (String) -> Void) {
        self.onChoose = onChoose
        super.init(frame: .zero)
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.textColor = .clear; field.alphaValue = 0.01; field.delegate = self
        field.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        addSubview(field)
        button.isBordered = false; button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: nil)
        button.imagePosition = .imageLeft
        button.target = self; button.action = #selector(pick)
        button.setAccessibilityLabel("Choose an emoji")
        addSubview(button)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); button.frame = bounds }

    @objc private func pick() {
        guard let window else { return }
        previousResponder = window.firstResponder
        field.stringValue = ""
        window.makeFirstResponder(field); field.selectText(nil)
        if let editor = field.currentEditor() as? NSTextView { editor.drawsBackground = false }
        NSApp.orderFrontCharacterPalette(button)
    }
    func controlTextDidChange(_ notification: Notification) {
        guard !field.stringValue.isEmpty else { return }
        if let emoji = EmojiPickerButton.emoji(in: field.stringValue) { onChoose(emoji) }
        restoreFocus()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard command == #selector(NSResponder.cancelOperation(_:)) || command == #selector(NSResponder.insertNewline(_:)) else { return false }
        restoreFocus(); return true
    }
    func restoreFocus() {
        if let editor = field.currentEditor(), window?.firstResponder === editor {
            window?.makeFirstResponder(previousResponder)
        }
        previousResponder = nil
    }
}
