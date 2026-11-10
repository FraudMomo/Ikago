import SwiftUI

/// Picks the SwiftUI page for a ikago:// tab.
struct InternalPageView: View {
    let page: InternalPage
    let state: BrowserState
    weak var commands: BrowserCommands?
    var tabID: String? = nil

    var body: some View {
        let colors = state.palette
        Group {
            switch page {
            case .splitEmpty: EmptySplitPage(state: state, tabID: tabID)
            case .bookmarks: BookmarksPage(state: state, commands: commands)
            case .settings: SettingsPage(state: state, commands: commands)
            case .history: HistoryPage(state: state, commands: commands)
            case .downloads: DownloadsPage(colors: colors)
            }
        }
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .environment(\.pagePalette, colors)
        .glassButtons(colors.glass)
        .tint(colors.accent)
    }
}

/// Shared page layout: a large title and a centred, readable-width column with generous space around it.
struct PageScaffold<Content: View>: View {
    let title: String
    let colors: Palette
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = geometry.size.width < 480 ? 16 : 32
            let width = max(0, min(680, geometry.size.width - inset * 2))
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(title).font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(colors.text).minimumScaleFactor(0.7).lineLimit(1)
                            Spacer(minLength: 8)
                            trailing
                        }
                        if let subtitle {
                            Text(subtitle).font(.system(size: 13)).foregroundStyle(colors.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    content
                }
                .frame(width: width, alignment: .leading)
                .padding(.top, 36).padding(.bottom, 48)
                .frame(width: geometry.size.width, alignment: .top)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(colors.pageBackground)
        }
    }
}

/// A group of rows under a small, quiet heading, on a soft borderless panel.
struct PageSection<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: Content

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(spacing: 0) { content }
                .background(shape.fill(Color.primary.opacity(0.045)))
                .clipShape(shape)
            if let footer {
                Text(footer).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
        }
    }
}

/// One row in a PageSection: label on the left, a small control on the right.
struct PageRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: Trailing

    var body: some View {
        // Label beside the control; in a narrow window the control drops under the label.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                // A small ideal width lets long subtitles wrap instead of pushing the control below.
                label.frame(minWidth: 200, idealWidth: 200, maxWidth: .infinity, alignment: .leading)
                trailing.controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 6) {
                label
                trailing.controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13))
            if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// A row with a slider, its value and a Reset button that appears once it differs from the default.
struct SliderRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    var step = 1.0
    var format: (Double) -> String = { "\(Int($0)) pt" }

    var body: some View {
        PageRow(title: title, subtitle: subtitle) {
            HStack(spacing: 10) {
                Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                    .frame(minWidth: 140, maxWidth: 240)
                Text(format(value)).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
                Button("Reset") { withAnimation(.ikago) { value = defaultValue } }
                    .controlSize(.small)
                    .opacity(value == defaultValue ? 0 : 1)
                    .disabled(value == defaultValue)
            }
        }
    }
}

struct PageDivider: View {
    var body: some View { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.leading, 16) }
}
