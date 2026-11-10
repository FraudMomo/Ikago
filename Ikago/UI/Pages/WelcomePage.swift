import AppKit
import SwiftUI

/// First-launch setup in a tab (ikago://welcome): engine, the default extension, search engine, then the first tab.
/// Every choice is an ordinary setting, so it can be changed later in Settings.
struct WelcomePage: View {
    @Bindable var state: BrowserState
    weak var commands: BrowserCommands?
    let tabID: String?
    @State private var step: WelcomeStep
    @State private var forward = true

    init(state: BrowserState, commands: BrowserCommands? = nil, tabID: String?, initialStep: WelcomeStep = .welcome) {
        self.state = state
        self.commands = commands
        self.tabID = tabID
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            ZStack {
                content
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: 460)
            .clipped()
            Spacer(minLength: 24)
            footer.frame(maxWidth: 460)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(state.palette.pageBackground)
        .foregroundStyle(state.palette.text)
        .buttonStyle(.automatic)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: WelcomeIntro()
        case .engine: WelcomeEngineStep(state: state)
        case .extensions: WelcomeExtensionsStep(state: state)
        case .search: WelcomeSearchStep(state: state)
        }
    }

    private var footer: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(WelcomeStep.allCases, id: \.self) { item in
                    Circle().fill(item == step ? Color.primary.opacity(0.7) : Color.primary.opacity(0.18)).frame(width: 6, height: 6)
                }
            }
            .accessibilityLabel("Step \((WelcomeStep.allCases.firstIndex(of: step) ?? 0) + 1) of \(WelcomeStep.allCases.count)")
            HStack {
                Button("Back") { go(-1) }.opacity(step == .welcome ? 0 : 1).disabled(step == .welcome)
                Spacer()
                if step == WelcomeStep.allCases.last {
                    Button(finishTitle, action: finish).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { go(1) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
        .controlSize(.large)
    }

    /// The chosen engine starts at launch, so choosing the one that isn't running means a relaunch.
    private var needsRelaunch: Bool { state.browserPreferences.preferredEngine != BrowserRuntime.engine }
    private var finishTitle: String { needsRelaunch ? "Relaunch and Start" : "Get Started" }

    private func go(_ offset: Int) {
        let all = WelcomeStep.allCases
        guard let index = all.firstIndex(of: step), all.indices.contains(index + offset) else { return }
        forward = offset > 0
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .ikago) { step = all[index + offset] }
    }

    private func finish() {
        if needsRelaunch {
            if let tabID { state.closeTab(tabID, removingPin: true) }
            state.saveNow()
            AppRelaunch.relaunch()
            return
        }
        commands?.newTab()
        if let tabID { state.closeTab(tabID, removingPin: true) }
    }
}

enum WelcomeStep: CaseIterable {
    case welcome, engine, extensions, search
}
