import AppKit
import WebKit
import SwiftUI

/// Settings ▸ Extensions ▸ Safari Extensions: every Safari extension in the apps on this Mac, found as soon as its app
/// is installed (`SafariExtensionScanner`), each with a switch. Turning one on for the first
/// time asks for its permissions; it then loads from its app and updates with it. They run on pages that open in WebKit.
struct SafariExtensionsSection: View {
    weak var commands: BrowserCommands?
    private var scanner: SafariExtensionScanner { .shared }
    private var manager: ExtensionManager { .shared }

    var body: some View {
        PageSection(title: "Safari Extensions", footer: footer) {
            let rows = self.rows
            if rows.isEmpty {
                PageRow(title: "No Safari extensions on this Mac",
                        subtitle: "Get them from the App Store as you would for Safari. They show up here as soon as the app is installed.") {
                    Button("Open App Store") { if let url = URL(string: "macappstore://") { NSWorkspace.shared.open(url) } }
                }
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { PageDivider() }
                SafariExtensionRow(row: row, commands: commands)
            }
        }
        .onAppear { scanner.start() }
    }

    private var footer: String {
        let base = "Ikago finds the Safari extensions in your apps on its own; turn one on to use it."
        return BrowserRuntime.engine == .chromium
            ? base + " Chromium is your default engine, so they run on sites set to open in WebKit (Opens in, in the site card)."
            : base
    }

    /// Found on this Mac, plus added ones whose app has since gone (so they can be removed).
    private var rows: [SafariExtensionRow.Model] {
        let records = Dictionary(manager.records.compactMap { record in record.appexPath.map { ($0, record) } }) { a, _ in a }
        var rows = scanner.found.map { SafariExtensionRow.Model(appex: $0.appex, app: $0.app, name: $0.name, record: records[$0.appex.path], kind: $0.kind) }
        let shown = Set(rows.map(\.appex.path))
        for (path, record) in records where !shown.contains(path) && !FileManager.default.fileExists(atPath: path) {
            let appex = URL(fileURLWithPath: path)
            let app = appex.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            rows.append(.init(appex: appex, app: app, name: app.deletingPathExtension().lastPathComponent, record: record, missing: true))
        }
        return rows
    }
}

private struct SafariExtensionRow: View {
    struct Model: Identifiable {
        let appex: URL
        let app: URL
        let name: String
        let record: ExtensionManager.Record?
        var kind = SafariExtensionScanner.Found.Kind.web
        var missing = false
        var id: String { appex.path }
    }

    let row: Model
    weak var commands: BrowserCommands?
    private var manager: ExtensionManager { .shared }
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            line
            if expanded, let record = row.record, let descriptor = manager.accessDescriptors.first(where: { $0.key == record.id }) {
                ExtensionAccessDetails(ext: descriptor).transition(.opacity)
            }
        }
    }

    private var line: some View {
        HStack(spacing: 12) {
            if row.record?.enabled == true, !row.missing { ExtensionDetailsButton(expanded: $expanded).padding(.trailing, -6) }
            Image(nsImage: NSWorkspace.shared.icon(forFile: row.app.path)).resizable().interpolation(.high)
                .frame(width: 28, height: 28).opacity(row.missing || row.kind != .web ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(failure == nil ? Color.secondary : Color.orange).lineLimit(2)
            }
            Spacer()
            if row.missing, let record = row.record {
                Button("Remove") { manager.remove(record.id) }
            } else if row.kind != .web {
                Text("Safari only").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    .help(unsupportedHelp)
            } else {
                if let url = context?.optionsPageURL, isOn {
                    Button("Options") { commands?.openInNewTab(url.absoluteString) }
                }
                Toggle(row.name, isOn: Binding(get: { isOn }, set: { set($0) })).labelsHidden().toggleStyle(.switch)
            }
        }
        .padding(.vertical, 10)
        .disabled(row.record.map { manager.installing.contains($0.id) } ?? false)
    }

    private var context: WKWebExtensionContextBox? { row.record.flatMap { manager.contexts[$0.id] }.map(WKWebExtensionContextBox.init) }
    private var isOn: Bool { row.record?.enabled == true }
    private var failure: String? { row.record.flatMap { manager.failures[$0.id] } }

    private var detail: String {
        if row.missing { return "Its app is no longer on this Mac" }
        if row.kind == .safariOnly { return "A Safari app extension: it runs only inside Safari" }
        if row.kind == .contentBlocker { return "A Safari content blocker: it runs only inside Safari" }
        if let failure { return "Couldn’t load: \(failure)" }
        let app = row.app.deletingPathExtension().lastPathComponent
        let from = app == row.name ? "From its app" : "From \(app)"
        guard isOn else { return from }
        let version = context?.version.map { " · Version \($0)" } ?? ""
        return from + version + (BrowserRuntime.engine == .chromium ? " · On WebKit pages" : "")
    }

    private var unsupportedHelp: String {
        "Built with Safari’s own extension system, which only Safari can run. Ikago runs Safari web extensions, and Chrome Web Store extensions on Chromium."
    }

    /// The first time asks for its permissions (and adds it); after that the switch only turns it on or off.
    private func set(_ on: Bool) {
        if let record = row.record { Task { await manager.setEnabled(record.id, on) } }
        else if on { commands?.installSafariExtension(at: row.appex) }
    }
}

/// The loaded extension's version and options page, for the row.
@MainActor
private struct WKWebExtensionContextBox {
    let version: String?
    let optionsPageURL: URL?
    init(_ context: WKWebExtensionContext) {
        version = context.webExtension.displayVersion
        optionsPageURL = context.optionsPageURL
    }
}
