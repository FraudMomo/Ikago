import AppKit

/// A Chromium page moved to another window and back keeps its native view and its page state (`BrowserWindows`).
/// The second window stays hidden, like every check window.
@MainActor
enum CEFWindowMoveChecks {
    static func run(_ shell: BrowserWindowController, tab id: String, page: WebTab) async throws {
        let previous = BrowserWindows.primary
        BrowserWindows.primary = shell
        defer { BrowserWindows.primary = previous }
        guard let other = BrowserWindows.open(frame: shell.window?.frame, show: false),
              BrowserWindows.move(id, to: other) else { throw CEFError.script("Moving a tab to another window failed.") }
        try await wait { page.contentView.window === other.window && page.contentView.bounds.width > 0 }
        guard other.content.controller(for: id)?.page === page, shell.content.controller(for: id) == nil,
              try await page.evaluate("window.fixtureLayoutIdentity") as? String == "retained" else {
            throw CEFError.script("A tab moved to another window reloaded or lost its page.")
        }
        BrowserWindows.bring(id, into: shell.state)
        try await wait { page.contentView.window === shell.window && BrowserWindows.others.isEmpty }
        guard shell.content.controller(for: id)?.page === page,
              try await page.evaluate("window.fixtureLayoutIdentity") as? String == "retained" else {
            throw CEFError.script("A tab brought back from another window reloaded or lost its page.")
        }
    }

    private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(50)) }
        throw CEFError.script("Moving a page between windows timed out.")
    }
}
