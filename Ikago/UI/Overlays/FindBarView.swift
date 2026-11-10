import SwiftUI

@MainActor
@Observable
final class FindBarModel {
    var text = ""
    var matchCount = 0
    var activeMatch = 0
    @ObservationIgnored var onSearch: (_ text: String, _ forward: Bool, _ findNext: Bool) -> Void = { _, _, _ in }
    @ObservationIgnored var onClose: () -> Void = {}

    func search(forward: Bool = true, next: Bool = false) {
        guard !text.isEmpty else {
            matchCount = 0
            activeMatch = 0
            return
        }
        onSearch(text, forward, next)
    }
}

/// ⌘F find-in-page: a glass capsule floating over the top-right of the page.
struct FindBarView: View {
    @Bindable var model: FindBarModel
    let colors: Palette
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in page", text: $model.text)
                .textFieldStyle(.plain)
                .focused($focused)
                .frame(width: 190)
                .onChange(of: model.text) { model.search() }
                .onSubmit { model.search(forward: !NSEvent.modifierFlags.contains(.shift), next: true) }
                .onKeyPress(.escape) { model.onClose(); return .handled }
            if !model.text.isEmpty && model.matchCount == 0 {
                Text("Not found").font(.caption).foregroundStyle(.secondary).transition(.opacity)
            }
            Button { model.search(forward: false, next: true) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).help("Previous (⇧↩)")
            Button { model.search(forward: true, next: true) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).help("Next (↩)")
            Button { model.onClose() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).help("Close (Esc)")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .frame(height: 40)
        .surface(Capsule(), colors)
        .fixedSize()
        .animation(.ikagoQuick, value: model.matchCount)
        .onAppear { focused = true }
    }
}
