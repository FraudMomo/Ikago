import SwiftUI

/// Sheet for a new Space: name, icon, and whether it gets its own logins and cookies.
struct NewSpaceView: View {
    let onCreate: (_ name: String, _ symbol: String, _ isolated: Bool) -> Void
    let onCancel: () -> Void
    var submitRequest = 0
    var colors: Palette
    @FocusState private var focused: Bool
    @State private var name = ""
    @State private var symbol = SpaceProfile.symbols[1]
    @State private var isolated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModalHeading(title: "New Space", subtitle: "A place for your tabs", colors: colors, close: onCancel)
            TextField("Name", text: $name, prompt: Text("Work, Study, Side Project…"))
                .modalInput(colors).focused($focused)
                .onSubmit(create)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 8) {
                ForEach(SpaceProfile.symbols, id: \.self) { candidate in
                    Button { symbol = candidate } label: {
                        Image(systemName: candidate)
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(candidate == symbol ? colors.selected : colors.hover))
                    }
                    .buttonStyle(.plain)
                }
            }
            Toggle(isOn: $isolated) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Separate logins and cookies").font(.system(size: 13))
                    Text("Keep this Space’s accounts separate.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.toggleStyle(.switch).controlSize(.small)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                    .buttonStyle(ModalButtonStyle(colors: colors))
                Button("Create Space", action: create).keyboardShortcut(.defaultAction)
                    .buttonStyle(ModalButtonStyle(colors: colors, primary: true))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .modalCard(colors, width: 360)
        .onAppear { focused = true }
        .onChange(of: submitRequest) { _, _ in create() }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { onCancel(); return }
        onCreate(String(trimmed.prefix(40)), symbol, isolated)
    }
}
