import AppKit
import SwiftUI

/// A step's heading: a large title and one plain line under it.
private struct StepHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 26, weight: .semibold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A selectable row: icon, title and detail, with a check when chosen.
private struct ChoiceRow<Icon: View>: View {
    let title: String
    let detail: String
    let selected: Bool
    @ViewBuilder let icon: Icon
    let action: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .medium))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17)).foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(14)
            .background(shape.fill(Color.primary.opacity(0.045)))
            .overlay(shape.strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct WelcomeIntro: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
            StepHeading(title: "Welcome to Ikago", subtitle: "A calm, native browser for your Mac. Three quick choices and you’re ready.")
        }
    }
}

struct WelcomeEngineStep: View {
    @Bindable var state: BrowserState

    var body: some View {
        VStack(spacing: 22) {
            StepHeading(title: "Choose an engine", subtitle: "You can switch any time, or pick an engine per site, in Settings.")
            VStack(spacing: 10) {
                ForEach(BrowserEngine.allCases) { engine in
                    ChoiceRow(title: engine.title, detail: detail(engine), selected: state.browserPreferences.preferredEngine == engine) {
                        EngineLogo(engine: engine, size: 32)
                    } action: {
                        state.browserPreferences.preferredEngine = engine
                    }
                }
            }
        }
    }

    private func detail(_ engine: BrowserEngine) -> String {
        engine == .webkit ? "Built into macOS · Apple Passwords and protected video" : "Open source · widest site compatibility"
    }
}

struct WelcomeExtensionsStep: View {
    let state: BrowserState
    @State private var blocker = ExtensionSync.entries().first { $0.id == ExtensionSync.defaults[0] }?.enabled ?? true

    var body: some View {
        VStack(spacing: 22) {
            StepHeading(title: "Extensions", subtitle: "Ikago starts with one extension. Add more from the Chrome Web Store later.")
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(Circle().fill(Color(hex: 0x800000)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("uBlock Origin Lite").font(.system(size: 14, weight: .medium))
                    Text("Blocks ads and trackers").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Toggle("uBlock Origin Lite", isOn: $blocker).labelsHidden().toggleStyle(.switch)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
        }
        .onChange(of: blocker) { _, on in apply(on) }
    }

    /// Records the choice in the extension ledger, then lets the running engines catch up with it.
    private func apply(_ on: Bool) {
        ExtensionSync.setEnabled(ExtensionSync.defaults[0], on)
        let profile = state.activeSpace.profileID
        Task {
            if BrowserRuntime.runs(.chromium) { await ChromiumExtensions.shared.sync(profile: profile) }
            if BrowserRuntime.runs(.webkit) { await ExtensionManager.shared.syncWithOtherEngine() }
        }
    }
}

struct WelcomeSearchStep: View {
    @Bindable var state: BrowserState

    var body: some View {
        VStack(spacing: 22) {
            StepHeading(title: "Search engine", subtitle: "Used when what you type in the address bar isn’t an address.")
            VStack(spacing: 10) {
                ForEach(SearchEngine.allCases) { engine in
                    ChoiceRow(title: engine.name, detail: detail(engine), selected: state.searchEngine == engine) {
                        Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                            .frame(width: 32, height: 32).background(Circle().fill(Color.primary.opacity(0.07)))
                    } action: {
                        state.searchEngine = engine
                    }
                }
            }
        }
    }

    private func detail(_ engine: SearchEngine) -> String {
        switch engine {
        case .google: "The most widely used"
        case .duckduckgo: "Doesn’t profile your searches"
        case .bing: "From Microsoft"
        }
    }
}
