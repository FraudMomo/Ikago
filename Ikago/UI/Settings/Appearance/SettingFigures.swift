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
                ZStack(alignment: .leading) {
                    // Page Title has no field at rest: the words sit on the bar.
                    RoundedRectangle(cornerRadius: 3).fill(colors.text.opacity(style == .title ? 0 : 0.07))
                    switch style {
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

/// The sidebar as chosen: full rows, a rail of icons, hidden (sliding in over the page at the window's edge, under the
/// pointer), or off.
struct SidebarModeFigure: View {
    let mode: SidebarMode
    /// Top Tabs: its sidebar is the icon rail.
    var rail = false
    let colors: Palette

    var body: some View {
        FigureWindow(colors: colors) {
            ZStack(alignment: .leading) {
                HStack(spacing: 3) {
                    if mode == .full || mode == .icons { FigureSidebar(colors: colors, rail: mode == .icons).transition(.opacity) }
                    FigurePage(colors: colors)
                }
                if mode == .hidden {
                    FigureSidebar(colors: colors, rail: rail)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 3).fill(colors.panel).shadow(color: .black.opacity(0.2), radius: 2))
                        .padding(.vertical, 3)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Image(systemName: "cursorarrow").font(.system(size: 9)).foregroundStyle(colors.text.opacity(0.8))
                        .offset(x: rail ? 12 : 22, y: 4)
                }
            }
        }
        .animation(.ikagoQuick, value: mode)
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
    /// Color pills in tinted cards; off, a small marker over an indented folder list.
    let pills: Bool
    let colors: Palette

    var body: some View {
        let tint = Color.blue
        FigureWindow(colors: colors, lights: false) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1).fill(tint.opacity(pills ? 0.35 : 1)).frame(width: pills ? 26 : 5, height: 4)
                    RoundedRectangle(cornerRadius: 1).fill(colors.text.opacity(0.4)).frame(width: 20, height: 3)
                }
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1).fill(colors.figureLine).frame(width: pills ? 46 : 38, height: 3)
                        .padding(.leading, pills ? 2 : 9)
                }
            }
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { if pills { RoundedRectangle(cornerRadius: 4).fill(tint.opacity(0.16)) } }
        }
        .animation(.ikagoQuick, value: pills)
    }
}

/// Top Tabs: group chips in the tab row, or tiles in the icon sidebar.
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
