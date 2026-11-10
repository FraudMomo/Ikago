import SwiftUI

struct DownloadAnchors {
    var toolbar: Anchor<CGRect>?
    var page: Anchor<CGRect>?
}

struct DownloadsAnchorKey: PreferenceKey {
    static var defaultValue: DownloadAnchors { DownloadAnchors() }
    static func reduce(value: inout DownloadAnchors, nextValue: () -> DownloadAnchors) {
        let next = nextValue()
        value.toolbar = next.toolbar ?? value.toolbar
        value.page = next.page ?? value.page
    }
}

/// The transient automatic button and the customizable Downloads control use the same dropdown.
struct DownloadToolbarButton: View {
    let colors: Palette
    weak var commands: BrowserCommands?
    var size: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var completion = 0
    private var center: DownloadCenter { .shared }

    var body: some View {
        let reduceMotion = reduceMotion
        return Button { commands?.toggleDownloads() } label: {
            ZStack {
                if center.activeCount > 0 {
                    ProgressView(value: center.overallFraction).progressViewStyle(.circular).controlSize(.small)
                        .frame(width: max(18, size - 4), height: max(18, size - 4))
                    Image(systemName: "arrow.down").font(.system(size: 8, weight: .semibold))
                } else {
                    Image(systemName: "arrow.down.circle").font(.system(size: 14, weight: .medium))
                }
            }
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: completion) { content, lift in
                content.offset(y: reduceMotion ? 0 : lift)
            } keyframes: { _ in
                CubicKeyframe(-5, duration: 0.12)
                CubicKeyframe(0, duration: 0.16)
                CubicKeyframe(-1.5, duration: 0.10)
                CubicKeyframe(0, duration: 0.12)
            }
            .frame(width: size, height: size)
            .background(Circle().fill(commands?.downloadsPresented == true ? colors.selected : .clear))
            .contentShape(Circle())
            .glassControl(Circle(), colors)
        }
        .buttonStyle(.plain).foregroundStyle(colors.text).tint(colors.accent)
        .anchorPreference(key: DownloadsAnchorKey.self, value: .bounds) { DownloadAnchors(toolbar: $0) }
        .help(center.activeCount > 0 ? "\(center.activeCount) downloading · Downloads (⇧⌘J)" : "Downloads (⇧⌘J)")
        .accessibilityLabel("Downloads")
        .accessibilityValue(center.activeCount > 0 ? "\(center.activeCount) in progress" : "Download history")
        .onChange(of: center.items.filter(\.finished).map(\.id)) { old, new in
            if !Set(new).subtracting(old).isEmpty { completion += 1 }
        }
    }
}
