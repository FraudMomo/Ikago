import AppKit
import SwiftUI

/// ikago://home, the new-tab page when new tabs open Ikago Home (`NewTabMode.home`), after Safari's Start Page: your
/// bookmarks as a grid of tiles, folders as tiles you open in place, then the pages you visit most. A click opens the
/// page in this tab, ⌘-click in a new one. Customize chooses the sections and what new tabs open.
struct HomePage: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    /// The bookmark folder shown, nil for the top level.
    @State private var folderID: String?
    /// Bumped when the background image is replaced.
    @State private var imageVersion = 0

    var body: some View {
        let colors = state.palette
        GeometryReader { geometry in
            let width = max(0, min(880, geometry.size.width - 64))
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 34) {
                    searchButton(colors)
                    if showsFavorites { favorites(colors) }
                    if showsFrequent, !frequent.isEmpty {
                        HomeSection(title: "Frequently Visited", colors: colors) {
                            HomeGrid {
                                ForEach(frequent, id: \.url) { visit in
                                    HomeTile(title: visit.title.isEmpty ? AddressResolver.hostname(visit.url) : visit.title, colors: colors) {
                                        FaviconView(pageURL: visit.url, size: 28)
                                    } open: { open(visit.url) }
                                    .contextMenu { pageMenu(visit.url) }
                                }
                            }
                        }
                    }
                    customize(colors)
                }
                .frame(width: width, alignment: .leading)
                .padding(.top, max(40, geometry.size.height * 0.12)).padding(.bottom, 48)
                .frame(width: geometry.size.width)
            }
            .background(HomeBackdrop(state: state, version: imageVersion))
        }
        .onChange(of: state.bookmarkFolders) { if let folderID, !state.bookmarkFolders.contains(where: { $0.id == folderID }) { self.folderID = nil } }
    }

    private var showsFavorites: Bool { state.browserPreferences.homeShowsFavorites ?? true }
    private var showsFrequent: Bool { state.browserPreferences.homeShowsFrequent ?? true }

    /// The pages visited most, one per address, web pages only.
    private var frequent: [Visit] {
        var seen = Set<String>()
        return state.history
            .filter { AddressResolver.isWebURL($0.url) }
            .sorted { ($0.visits ?? 1, $0.time) > ($1.visits ?? 1, $1.time) }
            .filter { seen.insert(OmniboxURL.key($0.url)).inserted }
            .prefix(12).map { $0 }
    }

    // MARK: Sections

    /// A quiet field that opens the address bar, for starting with the keyboard or the pointer.
    private func searchButton(_ colors: Palette) -> some View {
        Button { commands?.showCommandPalette(newTab: false) } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium))
                Text("Search or enter address").font(.system(size: 15))
                Spacer()
                Text("⌘L").font(.system(size: 12, weight: .medium)).foregroundStyle(colors.tertiary)
            }
            .foregroundStyle(colors.secondary)
            .padding(.horizontal, 18).frame(height: 46)
            .background(Capsule().fill(colors.text.opacity(0.05)))
            .overlay(Capsule().strokeBorder(colors.separator, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func favorites(_ colors: Palette) -> some View {
        let folders = state.bookmarkChildren(of: folderID)
        let marks = state.bookmarks(in: folderID)
        let folder = folderID.flatMap { id in state.bookmarkFolders.first { $0.id == id } }
        HomeSection(title: folder?.name ?? "Favorites", colors: colors, back: folder.map { current in
            { withAnimation(.ikagoQuick) { folderID = current.parentID } }
        }) {
            if folders.isEmpty && marks.isEmpty {
                VStack(spacing: 10) {
                    Text(folderID == nil ? "Bookmarks you save show here." : "This folder is empty.")
                        .font(.system(size: 13)).foregroundStyle(colors.secondary)
                    if folderID == nil {
                        Button("Import Bookmarks…") {
                            state.pendingSettingsSection = "Import"
                            commands?.openPage(.settings)
                        }
                        .buttonStyle(SettingsButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                HomeGrid {
                    ForEach(folders) { child in
                        HomeTile(title: child.name, colors: colors) {
                            FolderPreview(icons: state.bookmarks(in: child.id).prefix(4).map { ($0.url, $0.favicon) }, colors: colors)
                        } open: {
                            withAnimation(.ikagoQuick) { folderID = child.id }
                        }
                        .contextMenu {
                            Button("Open All in New Tabs") { for mark in state.bookmarks(in: child.id) { commands?.openInNewTab(mark.url) } }
                            Button("Edit Bookmarks…") { commands?.openPage(.bookmarks) }
                        }
                    }
                    ForEach(marks) { mark in
                        HomeTile(title: mark.title.isEmpty ? AddressResolver.hostname(mark.url) : mark.title, colors: colors) {
                            FaviconView(pageURL: mark.url, iconURL: mark.favicon, size: 28)
                        } open: { open(mark.url) }
                        .contextMenu {
                            pageMenu(mark.url)
                            Divider()
                            Button("Edit Bookmarks…") { commands?.openPage(.bookmarks) }
                        }
                    }
                }
            }
        }
    }

    private func customize(_ colors: Palette) -> some View {
        HStack(spacing: 10) {
            Spacer()
            // A colour of the person's choosing; picking one replaces an image.
            ColorPicker("Background colour", selection: Binding(
                get: { state.browserPreferences.homeBackgroundColor.map { Color(hex: $0) } ?? colors.pageBackground },
                set: { color in
                    state.browserPreferences.homeBackgroundColor = color.hexValue
                    state.browserPreferences.homeBackgroundImage = nil
                }), supportsOpacity: false)
                .labelsHidden()
                .help("Background colour")
            Menu {
                Section("Background") {
                    Button("Choose Image…") {
                        if HomeBackground.choose() {
                            state.browserPreferences.homeBackgroundImage = true
                            imageVersion += 1
                        }
                    }
                    Toggle("Blur", isOn: Binding(get: { state.browserPreferences.homeBackgroundBlur == true },
                                                 set: { state.browserPreferences.homeBackgroundBlur = $0 ? true : nil }))
                        .disabled(state.browserPreferences.homeBackgroundImage != true && state.browserPreferences.homeBackgroundColor == nil)
                    Button("Plain") {
                        state.browserPreferences.homeBackgroundColor = nil
                        state.browserPreferences.homeBackgroundImage = nil
                        HomeBackground.remove()
                        imageVersion += 1
                    }
                    .disabled(state.browserPreferences.homeBackgroundImage != true && state.browserPreferences.homeBackgroundColor == nil)
                }
                Divider()
                Toggle("Favorites", isOn: Binding(get: { showsFavorites },
                                                  set: { state.browserPreferences.homeShowsFavorites = $0 ? nil : false }))
                Toggle("Frequently Visited", isOn: Binding(get: { showsFrequent },
                                                           set: { state.browserPreferences.homeShowsFrequent = $0 ? nil : false }))
                Divider()
                Picker("New Tabs Open", selection: Binding(get: { state.newTabMode }, set: { state.newTabMode = $0 })) {
                    ForEach(NewTabMode.allCases) { Text($0.name).tag($0) }
                }
            } label: {
                Label("Customize", systemImage: "slider.horizontal.3").font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.button).buttonStyle(SettingsButtonStyle()).fixedSize()
        }
    }

    // MARK: Opening

    /// This tab, or with ⌘ a new one in the background, as links do.
    private func open(_ url: String) {
        if NSEvent.modifierFlags.contains(.command) { commands?.openInNewTab(url) } else { commands?.open(url, inNewTab: false) }
    }

    @ViewBuilder private func pageMenu(_ url: String) -> some View {
        Button("Open in New Tab") { commands?.openInNewTab(url) }
        Button("Copy Address") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
        }
    }
}

/// A heading over a group of tiles; inside a folder, a back chevron before it.
private struct HomeSection<Content: View>: View {
    let title: String
    let colors: Palette
    var back: (() -> Void)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                if let back {
                    Button(action: back) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(colors.secondary).help("Back")
                }
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(colors.text)
            }
            .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// Tiles in rows that fill the width, like Safari's Favorites.
private struct HomeGrid<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 104), spacing: 14, alignment: .top)], alignment: .leading, spacing: 18) {
            content
        }
    }
}

/// An icon on a rounded tile with its name under it; the tile lifts a little under the pointer.
private struct HomeTile<Icon: View>: View {
    let title: String
    let colors: Palette
    @ViewBuilder let icon: Icon
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: 8) {
                icon
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: Radius.card + 2, style: .continuous)
                        .fill(colors.text.opacity(hovering ? 0.09 : 0.05)))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card + 2, style: .continuous)
                        .strokeBorder(colors.separator, lineWidth: 0.5))
                    .scaleEffect(hovering ? 1.04 : 1)
                Text(title).font(.system(size: 11.5)).foregroundStyle(colors.text)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .frame(maxWidth: 92)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A folder's tile: the icons of its first four bookmarks in a 2×2 grid, or a folder symbol when it has none.
private struct FolderPreview: View {
    let icons: [(url: String, favicon: String?)]
    let colors: Palette

    var body: some View {
        if icons.isEmpty {
            Image(systemName: "folder").font(.system(size: 24, weight: .regular)).foregroundStyle(colors.secondary)
        } else {
            let columns = [GridItem(.fixed(20), spacing: 6), GridItem(.fixed(20), spacing: 6)]
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(icons.enumerated()), id: \.offset) { _, item in
                    FaviconView(pageURL: item.url, iconURL: item.favicon, size: 18).frame(width: 20, height: 20)
                }
            }
            .frame(width: 46)
        }
    }
}
