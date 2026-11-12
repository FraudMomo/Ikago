import SwiftUI

@MainActor @Observable
final class IntegratedTextPrompt: Identifiable {
    let id = UUID()
    let title: String
    let placeholder: String
    var text = ""
    private var completion: ((String?) -> Void)?
    init(title: String, placeholder: String, completion: @escaping (String?) -> Void) {
        self.title = title; self.placeholder = placeholder; self.completion = completion
    }
    func finish(_ value: String?) { let reply = completion; completion = nil; reply?(value) }
    func confirm() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        finish(value.isEmpty ? (placeholder.isEmpty ? nil : placeholder) : String(value.prefix(60)))
    }
}

struct IntegratedEditors: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    @FocusState private var focused: Bool
    var body: some View {
        if let prompt = chrome.textPrompt {
            backdrop { prompt.confirm() }
            VStack(alignment: .leading, spacing: 16) {
                Text(prompt.title).font(.headline)
                TextField(prompt.placeholder.isEmpty ? "Name" : prompt.placeholder,
                          text: Binding(get: { prompt.text }, set: { prompt.text = $0 }))
                    .textFieldStyle(.plain).font(.system(size: 20)).focused($focused)
                    .onSubmit { prompt.confirm() }
                Text("Return or click outside to save · Esc to cancel").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width: 350).surface(RoundedRectangle(cornerRadius: 18), state.palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { focused = true }.onExitCommand { prompt.finish(nil) }
        }
        if chrome.showNewSpace {
            backdrop { chrome.spaceSubmitRequest += 1 }
            NewSpaceView(onCreate: { name, symbol, isolated in
                state.createSpace(name: name, symbol: symbol, isolated: isolated); chrome.showNewSpace = false
            }, onCancel: { chrome.showNewSpace = false }, submitRequest: chrome.spaceSubmitRequest)
                .surface(RoundedRectangle(cornerRadius: 18), state.palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        if let id = chrome.editFolderID, let folder = state.folders.first(where: { $0.id == id }) {
            backdrop { chrome.editFolderID = nil }
            VStack(alignment: .leading, spacing: 18) {
                Text(folder.name).font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 6), spacing: 8) {
                    ForEach(TabFolder.iconChoices, id: \.symbol) { choice in
                        Button { state.setFolderIcon(id, to: choice.symbol) } label: {
                            Image(systemName: choice.symbol).frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 8).fill(folder.symbolIcon == choice.symbol ? state.palette.selected : state.palette.hover))
                        }.buttonStyle(.plain).accessibilityLabel(choice.name)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 5), spacing: 8) {
                    ForEach(FolderTag.allCases) { tag in
                        Button { state.setFolderTag(id, to: tag) } label: {
                            Circle().fill(tag.color).frame(width: 20, height: 20).padding(7)
                                .overlay(Circle().strokeBorder(.primary.opacity(folder.tag == tag.rawValue ? 0.7 : 0), lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityLabel(tag.name)
                    }
                }
                HStack { Button("Reset") { state.setFolderTag(id, to: nil); state.setFolderIcon(id, to: nil) }; Spacer(); Button("Emoji…") { chrome.editFolderID = nil; commands?.chooseFolderEmoji(id) } }
            }.padding(24).surface(RoundedRectangle(cornerRadius: 18), state.palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func backdrop(_ action: @escaping () -> Void) -> some View {
        Color.black.opacity(0.12).ignoresSafeArea().onTapGesture(perform: action).transition(.opacity)
    }
}
