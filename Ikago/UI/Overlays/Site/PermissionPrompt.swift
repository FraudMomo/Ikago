import SwiftUI

/// One permission prompt: the site, what it asks for, and how long to allow it. Queued by the window, one site and tab
/// at a time (`BrowserWindowController.finishPermission`).
struct PermissionPromptItem: Identifiable, Equatable {
    let id = UUID()
    let origin: String
    var kinds: PermissionRequest.Kinds
    let tabID: String
    let isPrivate: Bool
}

/// The permission prompt, in the window over the page (never a separate sheet window). Fail-closed: only an Allow
/// grants; Don't Allow blocks the site, and Esc or the close button deny just this request. A private window offers
/// only Allow Once, since it keeps nothing.
struct PermissionPrompt: View {
    let item: PermissionPromptItem
    let state: BrowserState
    let onChoice: (PermissionChoice) -> Void

    var body: some View {
        let colors = state.palette
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let tab = state.tab(item.tabID) { FaviconView(tab: tab, size: 20) } else { Image(systemName: "globe") }
                }
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.text.opacity(0.06)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(host).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                    Text("wants to \(item.kinds.phrase)").font(.system(size: 12.5)).foregroundStyle(colors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { onChoice(.dismiss) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(colors.secondary)
                        .frame(width: 22, height: 22).background(Circle().fill(colors.text.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Not now")
            }
            // What it asks for, one chip each, wrapping when there are many.
            FlowChips {
                ForEach(item.kinds.parts, id: \.rawValue) { kind in
                    HStack(spacing: 5) {
                        SettingTile(symbol: Self.symbol(kind), tint: Self.tint(kind)).scaleEffect(0.75).frame(width: 20, height: 20)
                        Text(Self.title(kind)).font(.system(size: 12, weight: .medium))
                    }
                    .padding(.leading, 3).padding(.trailing, 9).frame(height: 26)
                    .background(Capsule().fill(colors.text.opacity(0.06)))
                }
            }
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    choice(PermissionGrant.visit.title, primary: true, colors: colors) { onChoice(.allow(.visit)) }
                    if !item.isPrivate { choice(PermissionGrant.day.title, colors: colors) { onChoice(.allow(.day)) } }
                }
                HStack(spacing: 6) {
                    if !item.isPrivate { choice(PermissionGrant.always.title, colors: colors) { onChoice(.allow(.always)) } }
                    choice("Don't Allow", destructive: true, colors: colors) { onChoice(item.isPrivate ? .dismiss : .block) }
                }
            }
            Text(item.isPrivate ? "Private windows forget this when the tab leaves the site."
                 : "Change this any time from the site menu in the address bar.")
                .font(.system(size: 11)).foregroundStyle(colors.tertiary)
        }
        .padding(16)
        .frame(width: 372)
        .modalSurface(colors, radius: Radius.sheet, tint: 0.12)
        .foregroundStyle(colors.text)
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .onExitCommand { onChoice(.dismiss) }
        .animation(.ikagoQuick, value: item.kinds.rawValue)
    }

    private func choice(_ title: String, primary: Bool = false, destructive: Bool = false, colors: Palette,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: primary ? .semibold : .medium))
                .foregroundStyle(primary ? Color.white : destructive ? Color.red : colors.text)
                .frame(maxWidth: .infinity).frame(height: 32)
        }
        .buttonStyle(PromptButtonStyle(fill: primary ? colors.accent : destructive ? Color.red.opacity(0.1) : colors.text.opacity(0.07)))
    }

    private var host: String { URLComponents(string: item.origin)?.host ?? item.origin }

    static func title(_ kind: PermissionRequest.Kinds) -> String { kind.title }
    static func symbol(_ kind: PermissionRequest.Kinds) -> String { kind.info?.symbol ?? "hand.raised.fill" }
    /// Each kind's color, by family: devices warm, location and sensors green, data blue, the rest gray-indigo.
    static func tint(_ kind: PermissionRequest.Kinds) -> Color {
        switch kind {
        case .camera: .blue
        case .microphone: .orange
        case .notifications: .red
        case .location, .sensors: .green
        case .clipboard, .fileEditing, .downloads, .storageAccess: .cyan
        case .midi, .localNetwork, .virtualReality: .purple
        case .keyboardLock, .pointerLock, .windowManagement, .tabControl: .indigo
        default: .gray
        }
    }
}

/// Chips laid out in rows, wrapping to the next when one doesn't fit.
private struct FlowChips: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var items: [Int] = [], x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !items.isEmpty, x + size.width > width {
                rows.append((items, y, x - spacing, height))
                y += height + spacing; items = []; x = 0; height = 0
            }
            items.append(index); x += size.width + spacing; height = max(height, size.height)
        }
        if !items.isEmpty { rows.append((items, y, x - spacing, height)) }
        return rows
    }
}

/// A prompt button: a filled rounded rectangle, a touch brighter under the pointer and darker pressed.
private struct PromptButtonStyle: ButtonStyle {
    let fill: Color
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: Radius.control + 1, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: Radius.control + 1, style: .continuous)
                .fill(Color.primary.opacity(configuration.isPressed ? 0.1 : hovering ? 0.05 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: Radius.control + 1, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
