import AppKit
import SwiftUI

/// The media island at the bottom of the sidebar, after the iPhone's Dynamic Island: a black capsule with the artwork and
/// a wave in the artwork's color, opening into a card with the controls. Black glass when Liquid Glass is on, solid
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
    }

    private func island(_ tab: TabItem) -> some View {
        let art = MediaArtwork.shared.art(for: tab.playback.artwork)
        let glow = art?.glow ?? tab.themeColor.map(MediaArtwork.vivid) ?? .white.opacity(0.9)
        let shape = RoundedRectangle(cornerRadius: expanded ? 26 : 22, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { state.select(tab.id) } label: {
                    artwork(tab, art, size: expanded ? 44 : 28)
                }
                .buttonStyle(.plain).help("Show Playing Tab")
                Button { withAnimation(motion) { pinnedOpen.toggle() } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tab.playback.title.isEmpty ? tab.displayTitle : tab.playback.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if expanded {
                            Text(tab.playback.artist.isEmpty ? tab.addressLabel : tab.playback.artist)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "Collapse Player" : "Expand Player")
                MediaWaveform(levels: { [weak commands] in commands?.audioLevels(tab.id) },
                              active: tab.playback.playing && !tab.isMuted, color: glow)
                    .padding(.trailing, expanded ? 2 : 4)
            }
            if expanded {
                controls(tab)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .padding(.horizontal, expanded ? 14 : 6)
        .padding(.vertical, expanded ? 14 : 6)
        .background(alignment: .topLeading) {
            // The artwork's color, faintly, behind the open card.
            if expanded, art?.vivid == true { glow.opacity(0.16).blur(radius: 30).allowsHitTesting(false) }
        }
        .clipShape(shape)
        .surface(shape, islandColors, tintOpacity: 0.78)
        // Glass gets a fine edge of light; the flat panel already draws its own outline.
        .overlay { if islandColors.glass { shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5) } }
        .overlay(alignment: .topTrailing) { if hovering { closeButton } }
        .shadow(color: .black.opacity(expanded ? 0.3 : 0.18), radius: expanded ? 16 : 8, y: expanded ? 6 : 3)
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
        HStack(spacing: 0) {
            control(tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: tab.isMuted ? "Unmute" : "Mute", font: 13) { commands?.toggleMute(tab.id) }
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 18) {
                control(tab.playback.playing ? "pause.fill" : "play.fill",
                        label: tab.playback.playing ? "Pause" : "Play", font: 22) {
                    commands?.controlMedia(tab.id, action: tab.playback.playing ? .pause : .play)
                }
                control("forward.fill", label: "Next Track", enabled: tab.playback.canGoNext, font: 17) {
                    commands?.controlMedia(tab.id, action: .next)
                }
            }
            // Always takes its share, so the transport stays centred with one tab or several.
            ZStack(alignment: .trailing) { Color.clear.frame(height: 1); sources }.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func control(_ symbol: String, label: String, enabled: Bool = true, font: CGFloat,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: font, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.white)
                .frame(width: font + 16, height: font + 16)
                .contentShape(Circle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.3)
        .focused($controlsFocused)
        .help(label).accessibilityLabel(label)
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
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color(white: 0.22)))
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .offset(x: 5, y: -5)
        .transition(.opacity.combined(with: .scale(scale: 0.6)))
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
                Text("\(mediaTabs.count) tabs").font(.system(size: 10.5, weight: .medium))
            }
            .menuStyle(.borderlessButton).fixedSize().help("Choose Playing Tab")
        }
    }
}

extension Animation {
    /// The island opening and closing: a short spring with a little life in it, like the Dynamic Island's.
    static let island = Animation.spring(duration: 0.4, bounce: 0.18)
}
