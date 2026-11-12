import SwiftUI

struct TabAudioButton: View {
    let tab: TabItem
    let colors: Palette
    weak var commands: BrowserCommands?

    var body: some View {
        if tab.isMuted || tab.isPlayingAudio {
            Button { commands?.toggleMute(tab.id) } label: {
                Image(systemName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(colors.secondary)
            .help(tab.isMuted ? "Unmute Tab" : "Mute Tab")
            .accessibilityLabel("\(tab.isMuted ? "Unmute" : "Mute") \(tab.displayTitle)")
        }
    }
}
