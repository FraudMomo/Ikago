import SwiftUI

/// Tab list for the Top Bar layout. It never reserves page width or changes layouts.
struct TemporaryTabSidebar: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    weak var commands: BrowserCommands?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.12).contentShape(Rectangle())
                    .onTapGesture { dismiss() }
                VStack(spacing: 8) {
                    HStack {
                        Text("Tabs & Spaces").font(.headline)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).help("Close Tab Sidebar (Esc)")
                    }.padding(.horizontal, 16).padding(.top, 14)
                    Menu {
                        ForEach(state.spaces) { space in
                            Button { state.switchSpace(space.id) } label: {
                                Label(space.name, systemImage: space.symbol)
                            }
                        }
                        Divider()
                        Button("New Space…") { commands?.newSpace() }
                    } label: { Label(state.activeSpace.name, systemImage: state.activeSpace.symbol).frame(maxWidth: .infinity, alignment: .leading) }
                    .padding(.horizontal, 12)
                    TabListView(state: state, chrome: chrome, colors: state.palette, commands: commands, onSelection: dismiss)
                        .padding(.horizontal, 8)
                    SidebarMediaPlayer(state: state, commands: commands).padding(10)
                }
                .foregroundStyle(state.palette.text)
                .frame(width: min(320, max(0, geometry.size.width - 24)))
                .frame(maxHeight: .infinity)
                .surface(.rect(cornerRadius: 16), state.palette, translucentSidebar: state.browserPreferences.translucentSidebar == true)
                .padding(12)
                .padding(.top, state.topBarChromeHeight)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onChange(of: state.activeTabID) { _, _ in dismiss() }
    }

    private func dismiss() { withAnimation(.ikago) { chrome.showTabOverview = false } }
}
