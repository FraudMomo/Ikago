import AppKit
import SwiftUI

/// The red camera / microphone indicator on a tab. Clicking it mutes, resumes or ends the capture;
/// the microphone's menu also chooses the input device (the system default, see `AudioInputDevices`).
struct CaptureMenu: View {
    let tab: TabItem
    let microphone: Bool
    weak var commands: BrowserCommands?

    private var muted: Bool { microphone ? tab.microphoneMuted : tab.cameraMuted }
    private var noun: String { microphone ? "Microphone" : "Camera" }

    var body: some View {
        Menu {
            if (tab.engine ?? BrowserRuntime.engine) == .chromium {
                Button("Stop All Capture and Reload") { commands?.stopCapture(tab.id, microphone: microphone) }
                Text("Stops camera and microphone. Reload manually to allow capture again.")
            } else {
            Button(muted ? "Unmute \(noun)" : "Mute \(noun)") {
                commands?.setCaptureMuted(tab.id, microphone: microphone, muted: !muted)
            }
            Button("Stop Using \(noun)") { commands?.stopCapture(tab.id, microphone: microphone) }
            }
            if microphone {
                Divider()
                let current = AudioInputDevices.defaultID
                Section("Input Device (all apps)") {
                    ForEach(AudioInputDevices.all()) { device in
                        Toggle(device.name, isOn: Binding(get: { device.id == current },
                                                          set: { if $0 { AudioInputDevices.setDefault(device.id) } }))
                    }
                }
                Button("Sound Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension?input") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } label: {
            Image(systemName: microphone ? (muted ? "mic.slash.fill" : "mic.fill") : (muted ? "video.slash.fill" : "video.fill"))
                .font(.system(size: 10))
                .foregroundStyle(muted ? Color.secondary : Color.red)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(muted ? "\(noun) muted" : "Using your \(noun.lowercased())")
    }
}
