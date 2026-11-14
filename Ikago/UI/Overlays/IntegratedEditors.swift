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
                ModalHeading(title: prompt.title, colors: state.palette) { prompt.finish(nil) }
                TextField(prompt.placeholder.isEmpty ? "Name" : prompt.placeholder,
                          text: Binding(get: { prompt.text }, set: { prompt.text = $0 }))
                    .modalInput(state.palette).focused($focused)
                    .onSubmit { prompt.confirm() }
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { prompt.finish(nil) }.buttonStyle(ModalButtonStyle(colors: state.palette))
                    Button("Done") { prompt.confirm() }.buttonStyle(ModalButtonStyle(colors: state.palette, primary: true))
                        .keyboardShortcut(.defaultAction)
                }
            }.modalCard(state.palette, width: 380)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { focused = true }.onExitCommand { prompt.finish(nil) }
        }
        if chrome.showNewSpace {
            backdrop { chrome.spaceSubmitRequest += 1 }
            NewSpaceView(onCreate: { name, symbol, isolated in
                state.createSpace(name: name, symbol: symbol, isolated: isolated); chrome.showNewSpace = false
            }, onCancel: { chrome.showNewSpace = false }, submitRequest: chrome.spaceSubmitRequest, colors: state.palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        if let id = chrome.editFolderID, let folder = state.folders.first(where: { $0.id == id }) {
            backdrop { chrome.editFolderID = nil }
            GroupAppearanceEditor(folder: folder, state: state) { chrome.editFolderID = nil }
                .id(id).transition(.opacity.combined(with: .scale(scale: 0.97)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func backdrop(_ action: @escaping () -> Void) -> some View {
        Color.black.opacity(state.isDark ? 0.24 : 0.1).ignoresSafeArea().onTapGesture(perform: action).transition(.opacity)
    }
}
