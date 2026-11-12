import AppKit
import SwiftUI

/// The media island at the bottom of the sidebar, after the iPhone's Dynamic Island: a black capsule with the artwork and
/// track title, opening into a card with the controls. Black glass when Liquid Glass is on, solid
/// black when it is off. Closing it hides it until something new starts playing.
struct SidebarMediaPlayer: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var selectedID: String?
    @State private var pinnedOpen = false
    /// Mirrors keyboard focus on the controls, so opening for it can animate like hover does.
    @State private var focusOpen = false
    /// The tab the island shows, following `shown` inside this view's own animation, so the sidebar around it moves
    /// along instead of jumping: the model changes outside any animation.
    @State private var displayedID: String?
    /// What was playing when the island was closed; nil while it is shown. Something playing outside it brings it back.
    @State private var dismissed: Set<String>?
    @FocusState private var controlsFocused: Bool

    private var mediaTabs: [TabItem] { state.tabs.filter { $0.playback.available && !$0.isHibernating } }
    private var current: TabItem? {
        mediaTabs.first { $0.id == selectedID }
            ?? mediaTabs.first { $0.playback.playing }
            ?? mediaTabs.first
    }
    /// One key per playing tab and track, so a new track or a resumed tab counts as new playback.
    private var playingKeys: Set<String> {
        Set(mediaTabs.filter(\.playback.playing).map { "\($0.id)|\($0.playback.title)" })
    }
    private var shown: TabItem? { dismissed == nil ? current : nil }
    private var expanded: Bool { hovering || pinnedOpen || focusOpen }
    private var inactivityID: String { "\(shown?.id ?? "")|\(expanded)" }
    private var motion: Animation? { reduceMotion ? nil : .island }

    var body: some View {
        ZStack {
            if let tab = mediaTabs.first(where: { $0.id == displayedID }) {
                island(tab)
                    .transition(.asymmetric(insertion: .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity),
                                            removal: .scale(scale: 0.85, anchor: .bottom).combined(with: .opacity)))
            }
        }
        .onChange(of: shown?.id, initial: true) { _, id in
            guard id != displayedID else { return }
            withAnimation(motion) { displayedID = id }
        }
        .onChange(of: controlsFocused) { _, focused in withAnimation(motion) { focusOpen = focused } }
        .onChange(of: playingKeys) { _, keys in
            guard let dismissed else { return }
            // Forget what stopped, so playing it again counts as new; show again once anything else plays.
            let still = dismissed.intersection(keys)
            self.dismissed = keys.subtracting(still).isEmpty ? still : nil
        }
#if DEBUG
        .onAppear { if ProcessInfo.processInfo.environment["IKAGO_ISLAND_OPEN"] != nil { pinnedOpen = true } }
        .onReceive(NotificationCenter.default.publisher(for: .init("IkagoIslandToggle"))) { _ in
            withAnimation(motion) { pinnedOpen.toggle() }
        }
#endif
        .onChange(of: mediaTabs.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
        .task(id: inactivityID) {
            guard shown != nil, !expanded else { return }
            do { try await Task.sleep(for: .seconds(30)) }
            catch { return }
            guard !Task.isCancelled, shown != nil, !expanded else { return }
            withAnimation(motion) { dismissed = playingKeys }
        }
    }

    private func island(_ tab: TabItem) -> some View {
        let art = MediaArtwork.shared.art(for: tab.playback.artwork)
        let shape = RoundedRectangle(cornerRadius: expanded ? 22 : 20, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { state.select(tab.id) } label: {
                    artwork(tab, art, size: expanded ? 40 : 28)
                }
                .buttonStyle(.plain).help("Show Playing Tab")
                Button { withAnimation(motion) { pinnedOpen.toggle() } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tab.playback.title.isEmpty ? tab.displayTitle : tab.playback.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if expanded {
                            Text(tab.playback.artist.isEmpty ? tab.addressLabel : tab.playback.artist)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: expanded ? 40 : 28, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "Collapse Player" : "Expand Player")
                if expanded { sources }
                if tab.playback.hasVideo {
                    control("pip.enter", label: "Picture in Picture", font: 13) { commands?.pictureInPicture(tab.id) }
                        .recordLayout("media-pip-button")
                }
                closeButton
                    .frame(width: hovering || focusOpen ? 20 : 0).clipped()
                    .opacity(hovering || focusOpen ? 1 : 0)
                    .allowsHitTesting(hovering || focusOpen)
            }
            if expanded {
                controls(tab)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .padding(.horizontal, expanded ? 12 : 6)
        .padding(.vertical, expanded ? 12 : 6)
        .clipShape(shape)
        .surface(shape, islandColors, tintOpacity: 0.78)
        // Glass gets a fine edge of light; the flat panel already draws its own outline.
        .overlay { if islandColors.glass { shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5) } }
        .shadow(color: .black.opacity(0.2), radius: expanded ? 12 : 6, y: expanded ? 4 : 2)
        .environment(\.colorScheme, .dark)
        // Started here, so the whole sidebar takes part: the list above gives way as the island grows upward.
        .onHover { inside in withAnimation(motion) { hovering = inside } }
        .focusable(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media Player")
    }

    /// Black: tinted glass when Liquid Glass is on, a solid panel when it is off.
    private var islandColors: Palette { Palette(state.palette, over: .black, panelIsSurface: true) }

    private func artwork(_ tab: TabItem, _ art: MediaArtwork.Art?, size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        return ZStack {
            if let art {
                Image(nsImage: art.image).resizable().aspectRatio(contentMode: .fill)
            } else {
                shape.fill(.white.opacity(0.1))
                FaviconView(tab: tab, size: size * 0.55)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
    }

    private func controls(_ tab: TabItem) -> some View {
        // Equal outside buttons keep Play at the island's centre. The source picker lives in the header, so its
        // title/count can never shift the transport controls.
        HStack(spacing: 18) {
            control(tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: tab.isMuted ? "Unmute" : "Mute", font: 13) { commands?.toggleMute(tab.id) }
            control(tab.playback.playing ? "pause.fill" : "play.fill",
                    label: tab.playback.playing ? "Pause" : "Play", font: 20, prominent: true) {
                commands?.controlMedia(tab.id, action: tab.playback.playing ? .pause : .play)
            }
            control("forward.fill", label: "Next Track", enabled: tab.playback.canGoNext, font: 15) {
                commands?.controlMedia(tab.id, action: .next)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func control(_ symbol: String, label: String, enabled: Bool = true, font: CGFloat,
                         prominent: Bool = false, action: @escaping () -> Void) -> some View {
        MediaPlayerControl(symbol: symbol, label: label, font: font, prominent: prominent, action: action)
            .disabled(!enabled)
            .focused($controlsFocused)
    }

    private var closeButton: some View {
        Button {
            withAnimation(motion) {
                pinnedOpen = false
                dismissed = playingKeys
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20, height: 20)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focused($controlsFocused)
        .help("Close Player").accessibilityLabel("Close Player")
    }

    /// With several tabs playing, a menu to pick which one the island shows.
    @ViewBuilder private var sources: some View {
        if mediaTabs.count > 1 {
            Menu {
                ForEach(mediaTabs) { source in
                    Button(source.displayTitle) { selectedID = source.id }
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .focused($controlsFocused)
            .help("Choose Playing Tab").accessibilityLabel("Choose Playing Tab (\(mediaTabs.count) tabs)")
        }
    }
}

extension Animation {
    /// The island opening and closing: a short spring with a little life in it, like the Dynamic Island's.
    static let island = Animation.spring(duration: 0.4, bounce: 0.18)
}
