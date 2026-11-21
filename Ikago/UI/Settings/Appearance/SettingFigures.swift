import SwiftUI

/// Small drawings of what a setting changes, so a choice shows what it does before it is made. Every row's drawing is
/// the same size and sits in the same place, before the row's title (`PageRow.figure`); drawings of the whole window
/// carry its traffic lights, drawings of one part of it don't. Drawn in the Space's colors, like the layout cards.

// MARK: - Address bar styles

/// One address bar style (`TabsAddressStyle`) as a card: a drawn tab row and bar, the name under it.
struct TabsAddressCard: View {
    let style: TabsAddressStyle
    let selected: Bool
    let colors: Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                TabsAddressFigure(style: style, colors: colors)
                    .frame(height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Color.settingsAccent : .clear, lineWidth: 2))
                Text(style.name).font(.system(size: 12, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(style.summary)
        .accessibilityLabel(style.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct TabsAddressFigure: View {
    let style: TabsAddressStyle
    let colors: Palette

    var body: some View {
        let line = colors.text.opacity(0.16), strong = colors.text.opacity(0.55)
        VStack(spacing: 0) {
            // The tab row: the active tab meets the bar.
            HStack(alignment: .bottom, spacing: 5) {
                FigureLights().padding(.bottom, 3).padding(.trailing, 2)
                UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3).fill(colors.pageBackground).frame(width: 30, height: 10)
                RoundedRectangle(cornerRadius: 1.5).fill(line).frame(width: 22, height: 3).padding(.bottom, 3.5)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.top, 8)
            // The bar: controls, then the address in its style.
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(line).frame(width: 4, height: 4) }
                ZStack(alignment: style == .centered ? .center : .leading) {
                    // Page Title has no field at rest: the words sit on the bar.
                    RoundedRectangle(cornerRadius: 3).fill(colors.text.opacity(style == .title ? 0 : 0.07))
                    switch style {
                    case .centered:
                        Capsule().fill(strong).frame(width: 22, height: 3)
                    case .wide:
                        HStack(spacing: 1.5) {
                            Capsule().fill(strong).frame(width: 16, height: 3)
                            Capsule().fill(line.opacity(1.6)).frame(width: 34, height: 3)
                        }.padding(.leading, 5)
                    case .title:
                        // The site, then its title, quieter.
                        HStack(spacing: 4) {
                            Capsule().fill(strong).frame(width: 14, height: 3.5)
                            Capsule().fill(line.opacity(1.4)).frame(width: 34, height: 3)
                        }.padding(.leading, 3)
                    }
                }
                .frame(maxWidth: style == .centered ? 70 : .infinity)
                .frame(maxWidth: .infinity)
                .frame(height: 10)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(colors.pageBackground)
            colors.pageBackground.overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach([0.6, 0.8, 0.5], id: \.self) { w in Capsule().fill(line).frame(width: 90 * w, height: 2.5) }
                }.padding(8)
            }
        }
        .background(colors.tint)
    }
}

// MARK: - Frame

/// One row drawing's frame: the Space's window color, rounded, with a hairline; with `lights`, the window's traffic
/// lights in its corner and the content under them.
struct FigureWindow<Content: View>: View {
    let colors: Palette
    var lights = true
    @ViewBuilder let content: Content

    static var size: CGSize { CGSize(width: 80, height: 52) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            colors.tint
            content
                .padding(.top, lights ? 13 : 6).padding(.horizontal, 6).padding(.bottom, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if lights { FigureLights().padding(.leading, 6).padding(.top, 5) }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// The three window buttons, drawn small.
struct FigureLights: View {
    var body: some View {
        HStack(spacing: 2.5) {
            ForEach([Color(hex: 0xFF5F57), Color(hex: 0xFEBC2E), Color(hex: 0x28C840)], id: \.self) { Circle().fill($0).frame(width: 4, height: 4) }
        }
    }
}

private extension Palette {
    var figureLine: Color { text.opacity(0.18) }
    var figureStrong: Color { text.opacity(0.32) }
}

private struct FigurePage: View {
    let colors: Palette
    var body: some View { RoundedRectangle(cornerRadius: 3, style: .continuous).fill(colors.pageBackground) }
}

/// A full sidebar's rows, or a rail's icons.
private struct FigureSidebar: View {
    let colors: Palette
    var rail = false
    var rows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: rail ? 3 : 3.5) {
            ForEach(0..<rows, id: \.self) { i in
                if rail {
                    RoundedRectangle(cornerRadius: 1.5).fill(i == 1 ? colors.selected : colors.figureLine).frame(width: 6, height: 6)
                } else {
                    RoundedRectangle(cornerRadius: 1).fill(i == 1 ? colors.selected : colors.figureLine).frame(width: 16, height: 3)
                }
            }
        }
        .frame(width: rail ? 8 : 18, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Window and sidebar

/// The sidebar as chosen: full rows, a rail of icons, or hidden; on the left or right.
struct SidebarModeFigure: View {
    /// 0 full, 1 icons, 2 hidden (Settings ▸ Window and Sidebar).
    let mode: Int
    let onRight: Bool
    let colors: Palette

    var body: some View {
        FigureWindow(colors: colors) {
            HStack(spacing: 3) {
                if !onRight && mode < 2 { FigureSidebar(colors: colors, rail: mode == 1).transition(.opacity) }
                FigurePage(colors: colors)
                if onRight && mode < 2 { FigureSidebar(colors: colors, rail: mode == 1).transition(.opacity) }
            }
        }
        .animation(.ikagoQuick, value: mode)
        .animation(.ikagoQuick, value: onRight)
    }
}

/// A hidden sidebar sliding in at the window's edge under the pointer, or (off) staying away.
struct EdgePeekFigure: View {
    let on: Bool
    var rail = false
    let colors: Palette

    var body: some View {
        FigureWindow(colors: colors) {
            ZStack(alignment: .leading) {
                FigurePage(colors: colors)
                if on {
                    FigureSidebar(colors: colors, rail: rail)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 3).fill(colors.panel).shadow(color: .black.opacity(0.2), radius: 2))
                        .padding(.vertical, 3)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                Image(systemName: "cursorarrow").font(.system(size: 9)).foregroundStyle(colors.text.opacity(0.8))
                    .offset(x: on ? (rail ? 12 : 22) : -3, y: 4)
            }
        }
        .animation(.ikagoQuick, value: on)
    }
}

/// The icon sidebar under the pointer: Magnify turns the tile under it into a tab row over the page and the tiles beside
/// it into smaller ones, like a carousel; Expand widens the rail over the page with each name beside its icon.
struct RailHoverFigure: View {
    let effect: RailHoverEffect?
    let colors: Palette

    var body: some View {
        // Each icon's growth with the pointer on the middle one: 0 at rest, 1 under the pointer.
        let growth: [CGFloat] = effect == .magnify ? [0, 0.3, 1, 0.3, 0] : [0, 0, 0, 0, 0]
        FigureWindow(colors: colors) {
            ZStack(alignment: .topLeading) {
                FigurePage(colors: colors).padding(.leading, 13)
                VStack(spacing: 2.5) {
                    ForEach(Array(growth.enumerated()), id: \.offset) { index, grow in
                        // Each icon grows in place, inside its tile.
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(index == 2 && grow == 0 ? colors.selected : colors.figureLine)
                            .frame(width: 4, height: 4)
                            .scaleEffect(1 + 0.6 * grow)
                            .frame(width: 7, height: 5)
                    }
                }
                .padding(.top, 3)
                .frame(width: 11)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(RoundedRectangle(cornerRadius: 2).fill(colors.tint))
                // Magnify: the tile under the pointer as a tab row over the page, the ones beside it as smaller rows.
                if effect == .magnify {
                    VStack(alignment: .leading, spacing: 1.5) {
                        ForEach(0..<3, id: \.self) { index in
                            let main = index == 1, line: CGFloat = main ? 12 : 7
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 1.5).fill(colors.figureLine).frame(width: main ? 6.4 : 4.7, height: main ? 6.4 : 4.7)
                                Capsule().fill(colors.figureLine.opacity(main ? 1 : 0.6)).frame(width: line, height: 1.5)
                            }
                            .padding(.leading, main ? 2.3 : 3.1).padding(.trailing, 3)
                            .frame(height: main ? 8 : 6)
                            .background(RoundedRectangle(cornerRadius: 2).fill(colors.tint).shadow(color: .black.opacity(main ? 0.3 : 0.2), radius: 1.5))
                        }
                    }
                    .offset(x: 0.5, y: 10.5)
                    .transition(.opacity)
                }
                // Expand: the rail widened over the page, with names beside the icons.
                if effect == .expand {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach([14, 10, 16, 9], id: \.self) { width in
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 1).fill(colors.figureLine).frame(width: 4, height: 4)
                                Capsule().fill(colors.figureLine).frame(width: CGFloat(width), height: 1.5)
                            }
                        }
                    }
                    .padding(4)
                    .frame(width: 30, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(RoundedRectangle(cornerRadius: 2.5).fill(colors.tint).shadow(color: .black.opacity(0.3), radius: 2))
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                if effect != nil {
                    Image(systemName: "cursorarrow").font(.system(size: 9)).foregroundStyle(colors.text.opacity(0.8))
                        .offset(x: effect == .expand ? 18 : 14, y: effect == .expand ? 13 : 19)
                }
            }
        }
        .animation(.ikagoQuick, value: effect)
    }
}

/// The page's top edge that moves the window, drawn to scale: a band as tall as the chosen edge height.
struct EdgeHeightFigure: View {
    let height: Double
    let colors: Palette

    var body: some View {
        // The drawn page is about 30 pt tall, standing for about 120 pt of a real one, so 4–32 pt reads clearly.
        let band = max(1.5, height * 0.4)
        FigureWindow(colors: colors) {
            HStack(spacing: 3) {
                FigureSidebar(colors: colors)
                FigurePage(colors: colors)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.settingsAccent.opacity(0.3))
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.settingsAccent.opacity(0.75)).frame(height: 0.75) }
                            .frame(height: band)
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "hand.raised.fill").font(.system(size: 7)).foregroundStyle(colors.text.opacity(0.7))
                            .padding(.trailing, 6).offset(y: max(0, band / 2 - 4))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
        }
        .animation(.ikagoQuick, value: height)
    }
}

// MARK: - Pinned tabs and groups

/// Where pinned tabs sit: a grid at the top of the sidebar, or (off) rows in the list; in Top Tabs tiles in the
/// icon sidebar, or icon tabs at the start of the tab row.
struct PinnedTabsFigure: View {
    let shown: Bool
    let tabsLayout: Bool
    let colors: Palette

    var body: some View {
        let pin = colors.figureStrong
        FigureWindow(colors: colors, lights: !tabsLayout) {
            if tabsLayout {
                TabsWindow(colors: colors) {
                    if !shown { ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 1.5).fill(pin).frame(width: 5, height: 5) } }
                } rail: {
                    if shown { ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 1.5).fill(pin).frame(width: 6, height: 6) } }
                }
            } else {
                HStack(alignment: .top, spacing: 3) {
                    VStack(alignment: .leading, spacing: 3) {
                        if shown {
                            HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 1.5).fill(pin).frame(width: 5, height: 5) } }
                        } else {
                            ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 1).fill(pin).frame(width: 16, height: 3) }
                        }
                        ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 1).fill(colors.figureLine).frame(width: 16, height: 3) }
                    }
                    .frame(width: 18, alignment: .leading)
                    FigurePage(colors: colors)
                }
            }
        }
        .animation(.ikagoQuick, value: shown)
    }
}

/// Top Tabs drawn small: the lights and a tab row on top (with `row` before the tab), the rail (`rail` above its
/// icons) beside the page.
private struct TabsWindow<Row: View, Rail: View>: View {
    let colors: Palette
    @ViewBuilder let row: Row
    @ViewBuilder let rail: Rail

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .bottom, spacing: 2.5) {
                FigureLights().padding(.bottom, 2).padding(.trailing, 2)
                row
                UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2).fill(colors.pageBackground).frame(width: 16, height: 7)
                RoundedRectangle(cornerRadius: 1).fill(colors.figureLine).frame(width: 10, height: 2.5).padding(.bottom, 2)
            }
            HStack(alignment: .top, spacing: 3) {
                VStack(spacing: 2.5) {
                    rail
                    RoundedRectangle(cornerRadius: 1.5).fill(colors.figureLine).frame(width: 6, height: 6)
                }
                .frame(width: 8)
                FigurePage(colors: colors)
            }
        }
    }
}

/// The full sidebar's groups: tinted cards, or an indented folder list. Part of the sidebar, so no window.
struct GroupStyleFigure: View {
    let style: SidebarGroupStyle
    let colors: Palette

    var body: some View {
        let tint = Color.blue
        FigureWindow(colors: colors, lights: false) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1).fill(tint).frame(width: 5, height: 4)
                    RoundedRectangle(cornerRadius: 1).fill(colors.text.opacity(0.4)).frame(width: 20, height: 3)
                }
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1).fill(colors.figureLine).frame(width: style == .folders ? 38 : 46, height: 3)
                        .padding(.leading, style == .folders ? 9 : 2)
                }
            }
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { if style == .cards { RoundedRectangle(cornerRadius: 4).fill(tint.opacity(0.16)) } }
        }
        .animation(.ikagoQuick, value: style)
    }
}

/// Top Tabs: group chips in the tab row, tiles in the icon sidebar, or both.
struct GroupPlacementFigure: View {
    let placement: GroupPlacement
    let colors: Palette

    var body: some View {
        let chip = Color.blue
        FigureWindow(colors: colors, lights: false) {
            TabsWindow(colors: colors) {
                if placement != .sidebar { Capsule().fill(chip).frame(width: 8, height: 4).padding(.bottom, 1.5) }
            } rail: {
                if placement != .topBar { RoundedRectangle(cornerRadius: 1.5).fill(chip.opacity(0.85)).frame(width: 6, height: 6) }
            }
        }
        .animation(.ikagoQuick, value: placement)
    }
}

// MARK: - Motion

/// The tab highlight moving between rows the way the chosen style does. It plays while the pointer is over it, and a
/// few steps when the style changes; at rest it is still, so an open Settings page costs nothing (measured: looping
/// forever kept Ikago at ~10% CPU and WindowServer at ~37%). Part of the sidebar, so no window.
struct TabHighlightFigure: View {
    let style: TabHighlightStyle
    let colors: Palette
    @Namespace private var selection
    @State private var active = 0
    @State private var hovering = false
    @State private var demo = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FigureWindow(colors: colors, lights: false) {
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1).fill(colors.text.opacity(0.22)).frame(width: 36, height: 3)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 5).frame(height: 11)
                        .background(TabSelectionHighlight(shape: RoundedRectangle(cornerRadius: 3, style: .continuous), active: active == i,
                                                          color: colors.selected, selection: selection, id: "figure-highlight"))
                }
            }
            .environment(\.tabHighlightStyle, style)
        }
        .onHover { hovering = $0 }
        .onChange(of: style) { demo += 1 }
        .task(id: "\(hovering)-\(demo)-\(reduceMotion)") {
            guard !reduceMotion, hovering || demo > 0 else { return }
            var steps = hovering ? Int.max : 3
            while steps > 0, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(hovering ? 900 : 650))
                guard !Task.isCancelled else { return }
                active = (active + 1) % 3
                steps -= 1
            }
        }
    }
}

/// Switching tabs: the page fades into the next, or changes at once. Plays while the pointer is over it and once when
/// the setting changes; still at rest.
struct PageSwitchFigure: View {
    let instant: Bool
    let colors: Palette
    @State private var second = false
    @State private var hovering = false
    @State private var demo = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FigureWindow(colors: colors) {
            HStack(spacing: 3) {
                FigureSidebar(colors: colors, rows: 3)
                ZStack {
                    page(lines: [0.8, 0.5], accent: false).opacity(second ? 0 : 1)
                    page(lines: [0.4, 0.9], accent: true).opacity(second ? 1 : 0)
                }
            }
        }
        .onHover { hovering = $0 }
        .onChange(of: instant) { demo += 1 }
        .task(id: "\(hovering)-\(demo)-\(reduceMotion)") {
            guard !reduceMotion, hovering || demo > 0 else { return }
            var steps = hovering ? Int.max : 2
            while steps > 0, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(hovering ? 1100 : 500))
                guard !Task.isCancelled else { return }
                if instant { second.toggle() } else { withAnimation(.easeInOut(duration: 0.25)) { second.toggle() } }
                steps -= 1
            }
        }
    }

    private func page(lines: [CGFloat], accent: Bool) -> some View {
        FigurePage(colors: colors)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    RoundedRectangle(cornerRadius: 1).fill(accent ? Color.blue.opacity(0.7) : colors.text.opacity(0.35)).frame(width: 20, height: 3.5)
                    ForEach(lines, id: \.self) { w in Capsule().fill(colors.text.opacity(0.15)).frame(width: 40 * w, height: 2.5) }
                }
                .padding(4)
            }
    }
}

// MARK: - Spacing

/// The window with its sidebar and page, spaced as chosen: `inset` around everything, `gap` between sidebar and page.
struct WindowSpacingFigure: View {
    var inset: Double = 4
    var gap: Double = 6
    var onRight = false
    let colors: Palette

    var body: some View {
        // About a sixth of the real spacing, so 0–24 pt reads at this size.
        let border = CGFloat(inset) * 0.22, between = max(1, CGFloat(gap) * 0.3)
        FigureWindow(colors: colors) {
            HStack(spacing: between) {
                if !onRight { FigureSidebar(colors: colors) }
                FigurePage(colors: colors)
                if onRight { FigureSidebar(colors: colors) }
            }
            .padding(-2 + border)
        }
        .animation(.ikagoQuick, value: inset)
        .animation(.ikagoQuick, value: gap)
        .animation(.ikagoQuick, value: onRight)
    }
}

// MARK: - Moving the window

/// How the page's top edge moves the window: not at all, press and hold there, or a small header that drops down.
struct PageGrabFigure: View {
    let mode: PageGrabMode
    let colors: Palette

    var body: some View {
        FigureWindow(colors: colors) {
            HStack(spacing: 3) {
                FigureSidebar(colors: colors)
                FigurePage(colors: colors)
                    .overlay(alignment: .top) {
                        switch mode {
                        case .off:
                            EmptyView()
                        case .hold:
                            Image(systemName: "hand.raised.fill").font(.system(size: 8)).foregroundStyle(colors.text.opacity(0.7)).padding(.top, 2)
                        case .header:
                            Capsule().fill(colors.panel).frame(width: 22, height: 6)
                                .shadow(color: .black.opacity(0.2), radius: 1.5)
                                .overlay(Capsule().fill(colors.text.opacity(0.3)).frame(width: 8, height: 1.5))
                                .padding(.top, 2)
                        }
                    }
            }
        }
        .animation(.ikagoQuick, value: mode)
    }
}

/// Double-clicking the edge fills the screen: the window and the arrows that grow it.
struct ZoomFigure: View {
    let on: Bool
    let colors: Palette

    var body: some View {
        FigureWindow(colors: colors) {
            HStack(spacing: 3) {
                FigureSidebar(colors: colors)
                FigurePage(colors: colors)
                    .overlay {
                        Image(systemName: on ? "arrow.up.left.and.arrow.down.right" : "rectangle")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(colors.text.opacity(on ? 0.6 : 0.25))
                    }
            }
        }
        .animation(.ikagoQuick, value: on)
    }
}

// MARK: - Full screen

/// Full screen on a Mac with a camera housing: the page rises beside it, or a black band sits under it.
struct NotchFigure: View {
    let besideCamera: Bool
    let colors: Palette

    var body: some View {
        FigureWindow(colors: colors, lights: false) {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    Rectangle().fill(besideCamera ? colors.pageBackground : Color.black).frame(height: 7)
                    UnevenRoundedRectangle(bottomLeadingRadius: 2.5, bottomTrailingRadius: 2.5).fill(Color.black).frame(width: 20, height: 5)
                }
                FigurePage(colors: colors)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .padding(-2)
        }
        .animation(.ikagoQuick, value: besideCamera)
    }
}

// MARK: - Group counts

/// A collapsed group's header, with or without how many tabs it holds. Part of the sidebar, so no window.
struct TabCountFigure: View {
    let on: Bool
    let colors: Palette

    var body: some View {
        FigureWindow(colors: colors, lights: false) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach([(Color.blue, "3"), (Color.orange, "5")], id: \.1) { tint, count in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1).fill(tint).frame(width: 5, height: 4)
                        RoundedRectangle(cornerRadius: 1).fill(colors.text.opacity(0.4)).frame(width: 22, height: 3)
                        Spacer(minLength: 0)
                        Text(count).font(.system(size: 7, weight: .semibold).monospacedDigit()).foregroundStyle(colors.text.opacity(0.5))
                            .opacity(on ? 1 : 0)
                    }
                }
            }
            .padding(.horizontal, 3).padding(.top, 3)
        }
        .animation(.ikagoQuick, value: on)
    }
}
