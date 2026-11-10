import SwiftUI

/// WebKit's estimated progress, shared by every address presentation.
struct PageLoadProgress: View {
    let tab: TabItem?
    let colors: Palette
    /// A finished load runs the line to the end, then fades it out.
    @State private var finishing = false
    @State private var finish: Task<Void, Never>?

    var body: some View {
        Group {
            if let tab, tab.isLoading || finishing {
                // Scaled, not resized: growing the bar re-renders it without a layout pass on every progress tick.
                Rectangle().fill(colors.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 2)
                    .scaleEffect(x: finishing ? 1 : min(1, max(0.06, tab.progress)), y: 1, anchor: .leading)
                    .animation(.ikago, value: tab.progress)
                    .animation(.easeOut(duration: 0.2), value: finishing)
                .accessibilityLabel("Page loading")
                .accessibilityValue("\(Int(tab.progress * 100)) percent")
                .allowsHitTesting(false)
                .transition(.opacity.animation(.easeOut(duration: 0.25)))
            }
        }
        .onChange(of: tab?.isLoading) { was, loading in
            finish?.cancel()
            guard was == true, loading == false, tab?.loadError == nil else { finishing = false; return }
            finishing = true
            finish = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled { finishing = false }
            }
        }
        .onChange(of: tab?.id) { finish?.cancel(); finishing = false }
    }
}

struct PageLoadButton: View {
    let tab: TabItem
    let colors: Palette
    weak var commands: BrowserCommands?

    var body: some View {
        Button { commands?.reloadOrStop() } label: {
            Image(systemName: tab.isLoading ? "stop.fill" : "arrow.clockwise")
                .font(.system(size: 10, weight: .semibold)).frame(width: 18, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(colors.secondary)
        .help(tab.isLoading ? "Stop Loading (⌘.)" : "Reload (⌘R)")
        .accessibilityLabel(tab.isLoading ? "Stop loading" : "Reload page")
    }
}
