import SwiftUI

struct DownloadsDropdown: View {
    let colors: Palette
    weak var commands: BrowserCommands?
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var center: DownloadCenter { .shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Downloads").font(.system(size: 14, weight: .semibold))
                if center.activeCount > 0 {
                    Text("\(center.activeCount) active").font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundStyle(colors.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(colors.hover))
                }
                Spacer()
                Menu {
                    Button("Open Downloads Folder") { center.revealDownloadsFolder() }
                    Button("Clear Finished Downloads") { center.clearFinished() }
                        .disabled(!center.items.contains { !$0.inProgress })
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).foregroundStyle(colors.secondary)
                        .frame(width: 26, height: 26).contentShape(Circle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(colors.secondary).help("Download Actions")
                ChromeButton(symbol: "xmark", help: "Close Downloads and hide the temporary button when finished", colors: colors, size: 26, glass: false) {
                    center.dismissToolbarButton()
                    close()
                }.accessibilityLabel("Close Downloads and hide temporary button")
            }.padding(.horizontal, 16).padding(.vertical, 10)
            separator
            if center.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 28, weight: .light)).padding(.bottom, 4)
                    Text("No downloads yet").font(.system(size: 13, weight: .medium))
                    Text("Files you download will appear here.").font(.system(size: 12))
                }.foregroundStyle(colors.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(center.items.prefix(30)) { item in
                            DownloadRow(item: item, colors: colors, compact: true, onOpen: close)
                        }
                    }.padding(6)
                }.scrollIndicators(.never)
            }
            if let error = center.historyError { Text(error).font(.caption).foregroundStyle(.orange).padding(8) }
            separator
            Button { close(); commands?.openPage(.downloads) } label: {
                HStack {
                    Text("Show All Downloads")
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                }.font(.system(size: 12, weight: .medium)).foregroundStyle(colors.secondary)
                    .padding(.horizontal, 16).frame(height: 42).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .foregroundStyle(colors.text)
        .tint(colors.accent)
        .surface(.rect(cornerRadius: 16), colors)
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: .black.opacity(colors.isDark ? 0.22 : 0.1), radius: 18, y: 6)
        .animation(reduceMotion ? nil : .ikagoQuick, value: center.items.map(\.id))
    }

    private var separator: some View { Rectangle().fill(colors.separator).frame(height: 0.5).padding(.horizontal, 12) }
}

/// Anchored in the window's SwiftUI tree so glass samples the actual page.
struct DownloadsDropdownOverlay: View {
    let state: BrowserState
    let chrome: ChromeModel
    /// The Downloads button, in this overlay's coordinates.
    let anchor: CGRect?
    weak var commands: BrowserCommands?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastBounds: CGRect?

    var body: some View {
        GeometryReader { geometry in
            let measured = anchor
            let bounds = measured ?? lastBounds ?? CGRect(x: geometry.size.width - 40, y: state.tabLayout.usesTopTabs ? state.topBarChromeHeight : 42, width: 24, height: 24)
            let width = min(390, max(0, geometry.size.width - 24))
            let below = max(0, geometry.size.height - bounds.maxY - 20)
            let above = max(0, bounds.minY - 20)
            let desired = min(520, CGFloat(max(1, min(30, DownloadCenter.shared.items.count))) * 66 + 104)
            let height = min(desired, max(100, max(below, above)))
            let x = max(12, min(bounds.maxX - width, geometry.size.width - width - 12))
            let y = below >= height ? bounds.maxY + 8 : max(12, bounds.minY - height - 8)
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle()).onTapGesture { dismiss() }
                DownloadsDropdown(colors: state.tabLayout.usesTopTabs ? state.barPalette : state.palette, commands: commands, close: dismiss)
                    .frame(width: width, height: height).offset(x: x, y: y)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
            }
            .onAppear { lastBounds = measured }
            .onChange(of: measured) { _, value in if let value { lastBounds = value } }
        }
    }
    private func dismiss() { withAnimation(reduceMotion ? nil : .ikagoQuick) { chrome.showDownloads = false } }
}
