import SwiftUI

/// Sheet for a new Space: name, icon, and whether it gets its own logins and cookies.
struct NewSpaceView: View {
    let onCreate: (_ name: String, _ symbol: String, _ isolated: Bool) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @State private var symbol = SpaceProfile.symbols[1]
    @State private var isolated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Space").font(.headline)
            TextField("Name", text: $name, prompt: Text("Work, Study, Side Project…"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 6), spacing: 8) {
                ForEach(SpaceProfile.symbols, id: \.self) { candidate in
                    Button { symbol = candidate } label: {
                        Image(systemName: candidate)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(candidate == symbol ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Toggle(isOn: $isolated) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Separate logins and cookies")
                    Text("Sites in this Space won't see your other Spaces' accounts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Create Space", action: create).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onCreate(String(trimmed.prefix(40)), symbol, isolated)
    }
}
