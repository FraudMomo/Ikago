import SwiftUI

/// Small drawings beside settings that change how the window looks, so a choice shows what it does before it is made.
/// Drawn in the Space's colors, like the layout cards (`LayoutCard`).

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
                UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3).fill(colors.pageBackground).frame(width: 30, height: 10)
                RoundedRectangle(cornerRadius: 1.5).fill(line).frame(width: 22, height: 3).padding(.bottom, 3.5)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.top, 8)
            // The bar: controls, then the address in its style.
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(line).frame(width: 4, height: 4) }
                ZStack(alignment: style == .centered ? .center : .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(colors.text.opacity(0.07))
                    switch style {
                    case .centered:
                        Capsule().fill(strong).frame(width: 22, height: 3)
                    case .wide:
                        HStack(spacing: 1.5) {
                            Capsule().fill(strong).frame(width: 16, height: 3)
                            Capsule().fill(line.opacity(1.6)).frame(width: 34, height: 3)
                        }.padding(.leading, 5)
                    case .title:
                        HStack(spacing: 4) {
                            Capsule().fill(strong).frame(width: 30, height: 3.5)
                            Capsule().fill(line.opacity(1.4)).frame(width: 14, height: 3)
                        }.padding(.leading, 5)
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

// MARK: - Pinned tabs

/// Where pinned tabs sit: a grid at the top of the sidebar, or (off) rows in the list; in Sidebar + Tabs tiles in the
/// icon sidebar, or icon tabs at the start of the tab row.
struct PinnedTabsFigure: View {
    let shown: Bool
    let tabsLayout: Bool
    let colors: Palette

    var body: some View {
        let line = colors.text.opacity(0.16), pin = colors.text.opacity(0.32)
        ZStack(alignment: .topLeading) {
            colors.tint
            if tabsLayout {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 2) {
                        if !shown { ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 1.5).fill(pin).frame(width: 6, height: 6) } }
                        UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2).fill(colors.pageBackground).frame(width: 18, height: 7)
                        RoundedRectangle(cornerRadius: 1).fill(line).frame(width: 12, height: 2.5)
                    }
                    HStack(alignment: .top, spacing: 3) {
                        VStack(spacing: 2) {
                            if shown { ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 1.5).fill(pin).frame(width: 6, height: 6) } }
                            RoundedRectangle(cornerRadius: 1.5).fill(line).frame(width: 6, height: 6)
                        }
                        .frame(width: 8)
                        RoundedRectangle(cornerRadius: 3).fill(colors.pageBackground)
                    }
                }
                .padding(5)
            } else {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        if shown {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(7), spacing: 2), count: 3), spacing: 2) {
                                ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 1.5).fill(pin).frame(width: 7, height: 6) }
                            }
                        } else {
                            ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 1).fill(pin).frame(width: 22, height: 3) }
                        }
                        ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 1).fill(line).frame(width: 22, height: 3) }
                    }
                    .frame(width: 25, alignment: .leading)
                    RoundedRectangle(cornerRadius: 3).fill(colors.pageBackground)
                }
                .padding(5)
            }
        }
        .frame(width: 76, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .animation(.ikagoQuick, value: shown)
        .accessibilityHidden(true)
    }
}

// MARK: - Sidebar at the edge

/// A hidden sidebar sliding in from the window's edge under the pointer, or (off) staying away.
struct EdgePeekFigure: View {
    let on: Bool
    let colors: Palette

    var body: some View {
        ZStack(alignment: .leading) {
            colors.tint
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(colors.pageBackground).padding(5)
            if on {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(colors.panel)
                    .shadow(color: .black.opacity(0.18), radius: 3)
                    .overlay(alignment: .top) {
                        VStack(spacing: 3) {
                            ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 1).fill(colors.text.opacity(0.2)).frame(width: 14, height: 3) }
                        }.padding(.top, 7)
                    }
                    .frame(width: 22).padding(.vertical, 8).padding(.leading, 3)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Image(systemName: "cursorarrow").font(.system(size: 10)).foregroundStyle(colors.text.opacity(0.75))
                .offset(x: on ? 18 : 2, y: 6)
        }
        .frame(width: 76, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .animation(.ikagoQuick, value: on)
        .accessibilityHidden(true)
    }
}
