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
            VStack(alignment: .leading, spacing: 6) {
                label("Name")
                TextField("Name", text: $name, prompt: Text("Work, Study, Side Project…"))
                    .modalInput(colors).focused($focused)
                    .onSubmit(create)
            }
            VStack(alignment: .leading, spacing: 6) {
                label("Icon")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                    ForEach(SpaceProfile.symbols, id: \.self) { candidate in
                        let selected = candidate == symbol
                        Button { symbol = candidate } label: {
                            Image(systemName: candidate).font(.system(size: 14, weight: .medium))
                                .foregroundStyle(selected ? colors.accent : colors.secondary)
                                .frame(maxWidth: .infinity).frame(height: 32)
                                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                    .fill(selected ? colors.accent.opacity(0.12) : .clear))
                                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                    .strokeBorder(colors.accent.opacity(selected ? 0.45 : 0), lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(5)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.hover.opacity(0.8)))
            }
            Toggle(isOn: $isolated) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Separate logins and cookies").font(.system(size: 13))
                    Text("Keep this Space’s accounts separate.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.small)
            Rectangle().fill(colors.separator).frame(height: 0.5).padding(.horizontal, -20)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                    .buttonStyle(ModalButtonStyle(colors: colors))
                Button("Create Space", action: create).keyboardShortcut(.defaultAction)
                    .buttonStyle(ModalButtonStyle(colors: colors, primary: true))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .modalCard(colors, width: 380)
        .onAppear { focused = true }
        .onChange(of: submitRequest) { _, _ in create() }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(colors.secondary)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { onCancel(); return }
        onCreate(String(trimmed.prefix(40)), symbol, isolated)
    }
}
