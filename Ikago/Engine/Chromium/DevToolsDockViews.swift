import AppKit

/// The slim bar above docked DevTools: dock left, bottom, right or top,
/// and close. Native controls, so it works whatever DevTools draws below it.
final class DevToolsBar: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    static let height: CGFloat = 26
    var side: DevToolsDock.Side = .right { didSet { if side != oldValue { refresh() } } }
    private let onMove: (DevToolsDock.Side) -> Void
    private let onClose: () -> Void
    private var buttons: [DevToolsDock.Side: NSButton] = [:]

    private static let symbols: [(DevToolsDock.Side, String, String)] = [
        (.left, "rectangle.lefthalf.inset.filled", "Dock to Left"),
        (.bottom, "rectangle.bottomhalf.inset.filled", "Dock to Bottom"),
        (.right, "rectangle.righthalf.inset.filled", "Dock to Right"),
        (.top, "rectangle.tophalf.inset.filled", "Dock to Top"),
    ]

    init(move: @escaping (DevToolsDock.Side) -> Void, close: @escaping () -> Void) {
        onMove = move
        onClose = close
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (side, symbol, label) in Self.symbols {
            let button = Self.button(symbol, label) { [weak self] in self?.onMove(side) }
            buttons[side] = button
            stack.addArrangedSubview(button)
        }
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 14).isActive = true
        stack.addArrangedSubview(separator)
        stack.addArrangedSubview(Self.button("xmark", "Close Developer Tools (⌥⌘I)") { [weak self] in self?.onClose() })
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refresh()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        for (side, button) in buttons { button.contentTintColor = side == self.side ? .controlAccentColor : .secondaryLabelColor }
    }

    private static func button(_ symbol: String, _ label: String, action: @escaping () -> Void) -> NSButton {
        let button = ActionButton(action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        button.isBordered = false
        button.bezelStyle = .accessoryBarAction
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return button
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: isFlipped ? bounds.maxY - 1 : 0, width: bounds.width, height: 1).fill()
    }
}

private final class ActionButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private let handler: () -> Void
    init(action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        target = self
        self.action = #selector(run)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}

/// The gap between the page and DevTools: a hairline with a wider grab area, like a native split view.
final class DevToolsDivider: NSView {
    static let thickness: CGFloat = 5
    var vertical = true { didSet { if vertical != oldValue { needsDisplay = true; window?.invalidateCursorRects(for: self) } } }
    private let onDrag: (NSPoint) -> Void

    init(onDrag: @escaping (NSPoint) -> Void) {
        self.onDrag = onDrag
        super.init(frame: .zero)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: vertical ? .resizeLeftRight : .resizeUpDown) }
    // DevTools' own window is usually the active one, so the first press must already drag,
    // instead of only activating Ikago's window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    /// Follows the pointer until release in a tracking loop, so nothing else can take the drag midway.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            guard let superview else { return }
            onDrag(superview.convert(next.locationInWindow, from: nil))
            if next.type == .leftMouseUp { return }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        (vertical ? NSRect(x: bounds.midX, y: 0, width: 1, height: bounds.height)
                  : NSRect(x: 0, y: bounds.midY, width: bounds.width, height: 1)).fill()
    }
    override func accessibilityRole() -> NSAccessibility.Role? { .splitter }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityLabel() -> String? { "Resize Developer Tools" }
}
