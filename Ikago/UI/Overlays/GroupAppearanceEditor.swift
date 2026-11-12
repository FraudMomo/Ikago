import SwiftUI

/// A bounded editor with a live local preview; Done commits the draft together.
struct GroupAppearanceEditor: View {
    let folder: TabFolder
    let state: BrowserState
    let close: () -> Void
    @State private var icon: String?
    @State private var tag: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(folder: TabFolder, state: BrowserState, close: @escaping () -> Void) {
        self.folder = folder; self.state = state; self.close = close
        _icon = State(initialValue: folder.icon); _tag = State(initialValue: folder.tag)
    }
    private var preview: TabFolder { var value = folder; value.icon = icon; value.tag = tag; return value }
    private var color: Color { preview.tagValue?.color ?? state.palette.text }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 13) {
                FolderIcon(folder: preview, colors: state.palette, size: 23)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 16).fill(color.opacity(0.12)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.name).font(.system(size: 20, weight: .semibold)).tracking(-0.4).lineLimit(1)
                    Text("Group appearance").font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.top, 4)
                Spacer(minLength: 0)
                ModalCloseButton(colors: state.palette, action: close, label: "Cancel group appearance")
                    .recordLayout("group-editor-cancel")
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    section("Icon")
                    Spacer()
                    EmojiPickerButton { icon = $0 }.frame(width: 92, height: 24)
                        .recordLayout("emoji-picker-button")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 6), spacing: 5) {
                    ForEach(TabFolder.iconChoices, id: \.symbol) { choice in
                        let selected = preview.emojiIcon == nil && preview.symbolIcon == choice.symbol
                        Button { icon = choice.symbol == "folder.fill" ? nil : choice.symbol } label: {
                            Image(systemName: choice.symbol).font(.system(size: 16, weight: .medium))
                                .foregroundStyle(selected ? color : state.palette.secondary)
                                .frame(maxWidth: .infinity).frame(height: 32).contentShape(RoundedRectangle(cornerRadius: 10))
                                .background(RoundedRectangle(cornerRadius: 10).fill(selected ? color.opacity(0.12) : .clear))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(selected ? 0.5 : 0), lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel(choice.name).accessibilityAddTraits(selected ? .isSelected : [])
                            .recordLayout("group-editor-icon-\(choice.symbol)")
                    }
                }.padding(8).background(RoundedRectangle(cornerRadius: 15).fill(state.palette.hover.opacity(0.65)))
            }
            VStack(alignment: .leading, spacing: 10) {
                section("Color")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 10), spacing: 2) {
                    swatch(nil)
                    ForEach(FolderTag.allCases) { value in swatch(value) }
                }
            }
            Rectangle().fill(state.palette.separator).frame(height: 0.5)
            HStack {
                Button("Reset") { icon = nil; tag = nil }.font(.system(size: 12)).foregroundStyle(.secondary).buttonStyle(.plain)
                Spacer()
                Button("Done", action: save)
                    .buttonStyle(ModalButtonStyle(colors: state.palette, primary: true))
                    .keyboardShortcut(.defaultAction).recordLayout("group-editor-done")
            }
        }
        .modalCard(state.palette, width: 340)
        .onExitCommand(perform: close)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: icon)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: tag)
        .recordLayout("group-appearance-editor")
    }
    private func section(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
    }
    private func swatch(_ value: FolderTag?) -> some View {
        let selected = tag == value?.rawValue
        return Button { tag = value?.rawValue } label: {
            Circle().fill(value?.color ?? state.palette.hover)
                .frame(width: 20, height: 20)
                .overlay { if value == nil { Image(systemName: "nosign").font(.system(size: 12)).foregroundStyle(.secondary) } }
                .padding(3).overlay(Circle().strokeBorder(state.palette.text.opacity(selected ? 0.7 : 0), lineWidth: 1.5))
                .frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(value?.name ?? "No color").accessibilityAddTraits(selected ? .isSelected : [])
            .recordLayout("group-editor-color-\(value?.rawValue ?? "none")")
    }
    private func save() {
        withAnimation(reduceMotion ? nil : .ikagoQuick) {
            state.setFolderIcon(folder.id, to: icon)
            state.setFolderTag(folder.id, to: tag.flatMap(FolderTag.init(rawValue:)))
            close()
        }
    }
}
