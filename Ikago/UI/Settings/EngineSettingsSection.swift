import SwiftUI
import IKCEFBridge

/// Choose your engine: WebKit or Chromium, as two cards.
struct EngineSettingsSection: View {
    @Bindable var state: BrowserState

    private var chosen: BrowserEngine { state.browserPreferences.preferredEngine }

    var body: some View {
        PageSection(title: "Browser Engine",
                    footer: "Tabs, history and bookmarks stay the same, and most sign-ins carry over.") {
            VStack(spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) { cards }
                    VStack(spacing: 10) { cards }
                }
                if chosen != BrowserRuntime.engine {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                        Text("Relaunch to switch to \(chosen.title).").font(.system(size: 13))
                        Spacer(minLength: 8)
                        Button("Relaunch Now") { state.saveNow(); AppRelaunch.relaunch() }.buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(10)
            .animation(.ikagoQuick, value: chosen)
        }
        if chosen == .chromium || BrowserRuntime.runs(.chromium) {
            PageSection(title: "Chromium") {
                PageRow(title: "Translate X videos", subtitle: "Converts X’s H.264 video to AV1 on this Mac so it plays") {
                    Toggle("", isOn: Binding(get: { state.browserPreferences.chromiumVideoTranslation ?? true }, set: { on in
                        state.browserPreferences.chromiumVideoTranslation = on
                        state.saveNow()
                        MediaTranslation.apply(on)
                    })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                PageDivider()
                PageRow(title: "Live wave in the media player", subtitle: "Adds about 40 ms of audio delay") {
                    Toggle("", isOn: Binding(get: { state.browserPreferences.chromiumLiveWave == true }, set: { on in
                        state.browserPreferences.chromiumLiveWave = on ? true : nil
                        state.saveNow()
                        IKCEFAudio.enabled = on
                    })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder private var cards: some View {
        ForEach(BrowserEngine.allCases) { engine in
            EngineCard(engine: engine, selected: chosen == engine, running: BrowserRuntime.engine == engine) {
                state.browserPreferences.preferredEngine = engine
                state.saveNow()
            }
        }
    }
}

private struct EngineCard: View {
    let engine: BrowserEngine
    let selected: Bool
    let running: Bool
    let action: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    EngineLogo(engine: engine, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(engine.title).font(.system(size: 13, weight: .semibold))
                        Text(running ? "Running" : selected ? "After relaunch" : engine.tagline)
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15)).foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(engine.traits, id: \.title) { trait in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Image(systemName: trait.good ? "checkmark" : "minus")
                                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).frame(width: 10)
                            Text(trait.title).font(.system(size: 11)).foregroundStyle(trait.good ? .primary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(shape.fill(Color.primary.opacity(0.03)))
            .overlay(shape.strokeBorder(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 1.5 : 0.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(engine.title) engine")
    }
}

private extension BrowserEngine {
    var tagline: String { self == .webkit ? "Built into macOS" : "Open-source engine" }
    var traits: [(title: String, good: Bool)] {
        switch self {
        case .webkit:
            [("Apple Passwords and passkeys", true), ("Protected video such as Netflix", true), ("Updates with macOS", true)]
        case .chromium:
            [("Widest site compatibility", true), ("Docked DevTools", true), ("Automatic security updates", true)]
        }
    }
}
