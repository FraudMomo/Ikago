import AppKit
import SwiftUI

/// The media island at the bottom of the sidebar: one clean row with the artwork, the track and the controls you reach
/// for (play/pause, next), on the same glass as the sidebar's other controls (a flat panel with glass off). Clicking the
/// track opens it into a card with the artist, mute, picture in picture and the source picker. Closing it hides it until
/// something new starts playing.
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
    private var expanded: Bool { pinnedOpen || focusOpen }
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
        let colors = state.palette
        let shape = RoundedRectangle(cornerRadius: expanded ? Radius.sheet : Radius.card, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: 9) {
                Button { state.select(tab.id) } label: {
                    artwork(tab, art, size: expanded ? 40 : 30)
                }
                .buttonStyle(.plain).help("Show Playing Tab")
                Button { withAnimation(motion) { pinnedOpen.toggle() } } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tab.playback.title.isEmpty ? tab.displayTitle : tab.playback.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(colors.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(tab.playback.artist.isEmpty ? tab.addressLabel : tab.playback.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(colors.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, minHeight: expanded ? 40 : 30, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Collapse Player" : "More Controls")
                if expanded {
                    sources
                    closeButton.transition(.opacity)
                } else {
                    // The controls people reach for stay in the row; the rest are a click away.
                    if tab.playback.hasVideo {
                        control("pip.enter", label: "Picture in Picture", font: 11, compact: true) { commands?.pictureInPicture(tab.id) }
                            .recordLayout("media-pip-button")
                    }
                    control(tab.playback.playing ? "pause.fill" : "play.fill",
                            label: tab.playback.playing ? "Pause" : "Play", font: 13, compact: true) {
                        commands?.controlMedia(tab.id, action: tab.playback.playing ? .pause : .play)
                    }
                    if tab.playback.canGoNext {
                        control("forward.fill", label: "Next Track", font: 11, compact: true) {
                            commands?.controlMedia(tab.id, action: .next)
                        }
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if !expanded {
                    closeButton
                        .background(Circle().fill(.regularMaterial))
                        .offset(x: 12, y: -12)
                        .opacity(hovering ? 1 : 0)
                        .allowsHitTesting(hovering)
                }
            }
            if expanded {
                controls(tab)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .padding(.leading, expanded ? 10 : 6)
        .padding(.trailing, expanded ? 8 : 4)
        .padding(.vertical, expanded ? 10 : 6)
        // Glass like the sidebar's other controls; with glass off a solid card in the page's color, so it stands apart
        // from the sidebar instead of melting into it.
        .background { if !colors.glass { shape.fill(colors.pageBackground) } }
        .glassControl(shape, colors, reacts: false)
        .overlay(shape.strokeBorder(colors.glass ? Color.white.opacity(colors.isDark ? 0.1 : 0.45) : colors.separator, lineWidth: 0.5)
            .allowsHitTesting(false))
        .shadow(color: .black.opacity(colors.isDark ? 0.22 : 0.08), radius: expanded ? 12 : 6, y: expanded ? 4 : 2)
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        // Started here, so the whole sidebar takes part: the list above gives way as the island grows upward.
        .onHover { inside in withAnimation(motion) { hovering = inside } }
        .focusable(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media Player")
    }

    private func artwork(_ tab: TabItem, _ art: MediaArtwork.Art?, size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        return ZStack {
            if let art {
                Image(nsImage: art.image).resizable().aspectRatio(contentMode: .fill)
            } else {
                shape.fill(.primary.opacity(0.08))
                FaviconView(tab: tab, size: size * 0.55)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func controls(_ tab: TabItem) -> some View {
        // Five equal slots, whatever the sidebar's width: Play always in the middle, PiP and mute to its left, Next to
        // its right. The source picker lives in the header, so its title/count can never shift the transport controls.
        HStack(spacing: 0) {
            Group {
                if tab.playback.hasVideo {
                    control("pip.enter", label: "Picture in Picture", font: 12) { commands?.pictureInPicture(tab.id) }
                } else { Color.clear }
            }.frame(maxWidth: .infinity)
            control(tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: tab.isMuted ? "Unmute" : "Mute", font: 12) { commands?.toggleMute(tab.id) }
                .frame(maxWidth: .infinity)
            control(tab.playback.playing ? "pause.fill" : "play.fill",
                    label: tab.playback.playing ? "Pause" : "Play", font: 17, prominent: true) {
                commands?.controlMedia(tab.id, action: tab.playback.playing ? .pause : .play)
            }
            .frame(maxWidth: .infinity)
            control("forward.fill", label: "Next Track", enabled: tab.playback.canGoNext, font: 13) {
                commands?.controlMedia(tab.id, action: .next)
            }
            .frame(maxWidth: .infinity)
            Color.clear.frame(maxWidth: .infinity)
        }
        .frame(height: 40)
    }

    private func control(_ symbol: String, label: String, enabled: Bool = true, font: CGFloat,
                         prominent: Bool = false, compact: Bool = false, action: @escaping () -> Void) -> some View {
        MediaPlayerControl(symbol: symbol, label: label, font: font, prominent: prominent, compact: compact, action: action)
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
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
