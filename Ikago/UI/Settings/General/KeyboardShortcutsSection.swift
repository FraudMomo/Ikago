import AppKit
import SwiftUI

/// Settings ▸ General ▸ Shortcuts: every menu command with its shortcut, each changeable. Click a shortcut and press
/// the new one (with ⌘ or ⌃, as menu shortcuts need); ⌫ removes it, Esc keeps it. A shortcut another command uses is
/// refused with its name. Reset puts one, or all, back.
struct KeyboardShortcutsSection: View {
    @Bindable var state: BrowserState
    @State private var query = ""
    @State private var recording: String?
    @State private var problem: (id: String, text: String)?

    var body: some View {
        let commands = KeyBindings.commands.filter { matches($0) }
        PageSection(title: "Keyboard Shortcuts",
                    footer: "Click a shortcut, then press the new one. It needs ⌘ or ⌃; ⌫ removes it and Esc keeps it. Ikago's shortcuts take priority over a website's own.") {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField("Search commands", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                }
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
                Button("Reset All") {
                    state.browserPreferences.keyBindings = nil
                    problem = nil
                }
                .buttonStyle(SettingsButtonStyle())
                .disabled(state.browserPreferences.keyBindings?.isEmpty ?? true)
            }
            .padding(.vertical, 12)
            ForEach(commands) { command in
                PageDivider()
                PageRow(title: command.title, subtitle: problem?.id == command.id ? problem?.text : command.menu) {
                    HStack(spacing: 6) {
                        if state.browserPreferences.keyBindings?[command.id] != nil {
                            Button { reset(command.id) } label: { Image(systemName: "arrow.uturn.backward") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Back to \(command.defaultCombo.isEmpty ? "none" : command.defaultCombo.display)")
                        }
                        recorder(command)
                    }
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func matches(_ command: KeyBindings.Command) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }
        let combo = KeyBindings.current(command.id, bindings: state.browserPreferences.keyBindings).display
        return command.title.localizedCaseInsensitiveContains(text) || command.menu.localizedCaseInsensitiveContains(text)
            || combo.localizedCaseInsensitiveContains(text)
    }

    private func recorder(_ command: KeyBindings.Command) -> some View {
        let combo = KeyBindings.current(command.id, bindings: state.browserPreferences.keyBindings)
        let active = recording == command.id
        return Button {
            active ? stopRecording() : startRecording(command.id)
        } label: {
            Text(active ? "Type shortcut…" : combo.isEmpty ? "None" : combo.display)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(active ? Color.settingsAccent : combo.isEmpty ? .secondary : .primary)
                .frame(minWidth: 84)
                .padding(.horizontal, 10).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(active ? Color.settingsAccent.opacity(0.12) : Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(active ? Color.settingsAccent : Color.primary.opacity(0.08), lineWidth: active ? 1.5 : 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(command.title) shortcut: \(combo.isEmpty ? "none" : combo.display)")
    }

    private func startRecording(_ id: String) {
        recording = id
        problem = nil
        KeyBindings.recordingWindow = NSApp.keyWindow
        KeyBindings.recorder = { event in
            switch event.keyCode {
            case 53: stopRecording()  // Esc keeps it
            case 51, 117: set(id, .none)  // ⌫ removes it
            default:
                guard let combo = KeyCombo(event: event) else { return }
                guard combo.isUsable else { problem = (id, "Add ⌘ or ⌃ to the shortcut"); return }
                if let other = KeyBindings.conflict(for: combo, except: id, bindings: state.browserPreferences.keyBindings) {
                    problem = (id, "\(combo.display) is used by \(other.title)")
                    return
                }
                set(id, combo)
            }
        }
    }

    private func set(_ id: String, _ combo: KeyCombo) {
        let previous = state.browserPreferences.keyBindings
        var bindings = previous ?? [:]
        let builtIn = KeyBindings.commands.first { $0.id == id }?.defaultCombo
        if combo == builtIn { bindings[id] = nil } else { bindings[id] = combo }
        let next = bindings.isEmpty ? nil : bindings
        KeyBindings.apply(next)
        // macOS keeps a shortcut another menu item has (Copy, Hide…): say so and keep the old one.
        guard KeyBindings.menuHas(id, combo) else {
            KeyBindings.apply(previous)
            problem = (id, "\(combo.display) is taken by macOS or another menu")
            return
        }
        state.browserPreferences.keyBindings = next
        problem = nil
        stopRecording()
    }

    private func reset(_ id: String) {
        var bindings = state.browserPreferences.keyBindings ?? [:]
        bindings[id] = nil
        state.browserPreferences.keyBindings = bindings.isEmpty ? nil : bindings
    }

    private func stopRecording() {
        recording = nil
        KeyBindings.recorder = nil
        KeyBindings.recordingWindow = nil
    }
}
