import SwiftUI

/// Shared group typography with a choice of a small marker or a softly colored pill.
struct FolderLabel: View {
    let folder: TabFolder
    let colors: Palette
    var size: CGFloat = 12
    var isActive = false
    var style: GroupLabelStyle = .minimal

    var body: some View {
        Group {
            if style == .colorPill {
                HStack(spacing: 5) {
                    FolderIcon(folder: folder, colors: colors, size: size - 2)
                    title
                }
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill((folder.tagValue?.color ?? colors.tertiary)
                        .opacity(colors.isDark ? 0.28 : 0.22)))
            } else {
                HStack(spacing: 7) {
                    FolderIcon(folder: folder, colors: colors, size: size)
                    title
                }
            }
        }
    }

    private var title: some View {
        Text(folder.name)
            .lineLimit(1)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(isActive || style == .colorPill ? colors.text : colors.secondary)
    }
}

/// A group's icon: its emoji, or a symbol (a folder unless chosen) in the group's color.
struct FolderIcon: View {
    let folder: TabFolder
    let colors: Palette
    var size: CGFloat = 12

    var body: some View {
        Group {
            if let emoji = folder.emojiIcon {
                Text(emoji).font(.system(size: size + 1))
            } else {
                Image(systemName: folder.symbolIcon)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(folder.tagValue?.color ?? colors.secondary)
            }
        }
        .frame(width: size + 5, height: size + 4)
        .accessibilityHidden(true)
    }
}

extension TabFolder {
    /// The chosen icon when it is an emoji (anything that isn't an SF Symbol name).
    var emojiIcon: String? {
        guard let icon, !icon.isEmpty, NSImage(systemSymbolName: icon, accessibilityDescription: nil) == nil else { return nil }
        return icon
    }

    var symbolIcon: String {
        guard let icon, NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil else { return "folder.fill" }
        return icon
    }

    /// Symbols offered in the group's Icon menu.
    static let iconChoices: [(name: String, symbol: String)] = [
        ("Folder", "folder.fill"), ("Star", "star.fill"), ("Heart", "heart.fill"), ("Bookmark", "bookmark.fill"),
        ("Work", "briefcase.fill"), ("Home", "house.fill"), ("Book", "book.fill"), ("School", "graduationcap.fill"),
        ("Code", "chevron.left.forwardslash.chevron.right"), ("Design", "paintbrush.pointed.fill"), ("Chart", "chart.bar.fill"),
        ("Shopping", "cart.fill"), ("Travel", "airplane"), ("Music", "music.note"), ("Video", "play.rectangle.fill"),
        ("Games", "gamecontroller.fill"), ("News", "newspaper.fill"), ("Chat", "bubble.left.fill"), ("Idea", "lightbulb.fill"),
        ("Nature", "leaf.fill"), ("Fire", "flame.fill"), ("Bolt", "bolt.fill"), ("Sparkles", "sparkles"), ("Globe", "globe"),
    ]
}

extension TabFolder {
    func disclosureValue(count: Int, showsCount: Bool) -> String {
        let expansion = isOpen ? "Expanded" : "Collapsed"
        return showsCount ? "\(expansion), \(count) \(count == 1 ? "tab" : "tabs")" : expansion
    }

    func disclosureHelp(count: Int, showsCount: Bool) -> String {
        let action = "\(isOpen ? "Collapse" : "Expand") \(name)"
        return showsCount ? "\(action) · \(count) \(count == 1 ? "tab" : "tabs")" : action
    }
}

/// Right-click menu for a folder (sidebar header and top-bar chip).
struct FolderContextMenu: View {
    let folder: TabFolder
    let state: BrowserState
    weak var commands: BrowserCommands?

    var body: some View {
        Button("Rename Group…") { commands?.renameFolder(folder.id) }
        Menu("Icon") {
            ForEach(TabFolder.iconChoices, id: \.symbol) { choice in
                Button {
                    withAnimation(.ikago) { state.setFolderIcon(folder.id, to: choice.symbol == "folder.fill" ? nil : choice.symbol) }
                } label: {
                    Label(choice.name, systemImage: choice.symbol)
                    if folder.symbolIcon == choice.symbol && folder.emojiIcon == nil { Image(systemName: "checkmark") }
                }
            }
            Divider()
            Button(folder.emojiIcon.map { "Emoji: \($0)…" } ?? "Emoji…") { commands?.chooseFolderEmoji(folder.id) }
        }
        Menu("Color") {
            ForEach(FolderTag.allCases) { tag in
                Button { withAnimation(.ikago) { state.setFolderTag(folder.id, to: tag) } } label: {
                    Label { Text(tag.name) } icon: { Image(nsImage: tag.dot) }
                    if folder.tag == tag.rawValue { Image(systemName: "checkmark") }
                }
            }
            Divider()
            Button("None") { withAnimation(.ikago) { state.setFolderTag(folder.id, to: nil) } }
        }
        if folder.isClosed == true {
            Button("Reopen Group") { state.reopenFolder(folder.id) }
        } else if state.tabLayout.usesTopTabs {
            // Close Group: out of the strip, pages unloaded, reopenable from Tab ▸ Reopen Closed Group.
            Button("Close Group") { commands?.closeGroup(folder.id) }
        }
        Button("Delete Group") { withAnimation(.ikago) { state.deleteFolder(folder.id) } }
        Divider()
        Button("Close Tabs in Group") {
            for tab in state.tabs(in: folder) { commands?.closeTab(tab.id) }
        }
    }
}
