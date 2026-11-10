import SwiftUI

/// Live illustrations use the actual group label, so the choice matches both browser layouts.
struct GroupAppearanceSection: View {
    let state: BrowserState

    var body: some View {
        PageSection(title: "Tab Groups", footer: "Applies to the sidebar and top bar. Change a group's color from its context menu.") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) { cards(minimumWidth: 180) }
                VStack(spacing: 14) { cards(minimumWidth: 0) }
            }
            .padding(16)
            PageDivider()
            PageRow(title: "Show tab counts", subtitle: "Counts on collapsed groups and when hovering in the sidebar.") {
                Toggle("Show tab counts", isOn: Binding(
                    get: { state.showsGroupTabCounts },
                    set: { on in withAnimation(.ikago) { state.showsGroupTabCounts = on } }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }

    private func cards(minimumWidth: CGFloat) -> some View {
        ForEach(GroupLabelStyle.allCases) { style in
            GroupStyleCard(style: style, selected: state.groupLabelStyle == style,
                           showsCounts: state.showsGroupTabCounts, colors: state.palette) {
                withAnimation(.ikago) { state.groupLabelStyle = style }
            }
            .frame(minWidth: minimumWidth, maxWidth: .infinity)
        }
    }
}

private struct GroupStyleCard: View {
    let style: GroupLabelStyle
    let selected: Bool
    let showsCounts: Bool
    let colors: Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                illustration
                    .frame(height: 112)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(colors.tint))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? colors.accent : colors.separator, lineWidth: selected ? 2 : 1))
                    .accessibilityHidden(true)
                HStack {
                    Text(style.name).font(.system(size: 13, weight: selected ? .semibold : .regular))
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(colors.accent)
                        .opacity(selected ? 1 : 0)
                }
                Text(style.detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.name)
        .accessibilityValue(style.detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.ikagoQuick, value: selected)
    }

    private var illustration: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupLabel("Research", tag: .purple, expanded: true)
            HStack(spacing: 12) {
                Capsule().fill(FolderTag.purple.color.opacity(0.3)).frame(width: 1.5)
                VStack(alignment: .leading, spacing: 7) {
                    tabLine(width: 68)
                    tabLine(width: 48)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 29).padding(.leading, 3)
            groupLabel("Reading", tag: .teal, expanded: false)
        }
        .padding(14)
    }

    private func groupLabel(_ name: String, tag: FolderTag, expanded: Bool) -> some View {
        HStack {
            FolderLabel(folder: TabFolder(name: name, spaceID: SpaceProfile.defaultSpace.id, tag: tag.rawValue),
                        colors: colors, size: 11, style: style)
            Spacer(minLength: 0)
            if !expanded && showsCounts {
                Text("3").font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(colors.tertiary)
            }
            Image(systemName: "chevron.right").font(.system(size: 7, weight: .semibold))
                .rotationEffect(.degrees(expanded ? 90 : 0)).foregroundStyle(colors.tertiary)
        }
        .frame(height: 18)
    }

    private func tabLine(width: CGFloat) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2).fill(colors.tertiary).frame(width: 9, height: 9)
            Capsule().fill(colors.tertiary.opacity(0.65)).frame(width: width, height: 4)
        }
    }
}
