import SwiftUI

/// Clear Browsing Data: a period (last hour, today, since yesterday, all time, or custom dates) and what to remove, with
/// counts for the period. Opened over the window (`ChromeModel.showClearData`) by the History page, Settings and the
/// address bar's action; runs `BrowserState.clearData`.
struct ClearDataSheet: View {
    let state: BrowserState
    let close: () -> Void
    @State private var request = ClearDataRequest()
    @State private var clearing = false
    @State private var issue: String?

    var body: some View {
        let colors = state.palette
        let period = request.interval()
        let visits = state.visits(in: period)
        let searches = visits.filter(\.isSearch).count
        VStack(alignment: .leading, spacing: 16) {
            ModalHeading(title: "Clear Browsing Data", subtitle: "From every Space and window", colors: colors, close: close)
            HStack {
                Text("Time range").font(.system(size: 13)).foregroundStyle(colors.text)
                Spacer()
                Picker("Time range", selection: $request.period) {
                    ForEach(ClearDataRequest.Period.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            if request.period == .custom {
                HStack(spacing: 8) {
                    DatePicker("From", selection: $request.from, in: ...Date(), displayedComponents: .date)
                    DatePicker("To", selection: $request.to, in: ...Date(), displayedComponents: .date)
                }
                .font(.system(size: 12))
            }
            Rectangle().fill(colors.separator).frame(height: 0.5)
            VStack(alignment: .leading, spacing: 10) {
                option("Browsing history", detail: count(visits.count - searches, "page"), $request.history)
                option("Search history", detail: count(searches, "search", "searches"), $request.searches)
                option("Cookies and website data", detail: period == nil ? "Signs you out of most sites" : "From sites visited in this period",
                       $request.siteData)
                option("Cached images and files", detail: "Pages may load more slowly next time", $request.cache)
                option("Recently closed tabs", detail: count(state.windowGroup.reduce(0) { $0 + $1.closed.count }, "tab"), $request.closedTabs)
                option("Downloads list", detail: "The files stay on your Mac", $request.downloads)
                option("Site icons", detail: "Icons download again as you browse", $request.icons)
            }
            if let issue { Text(issue).font(.system(size: 12)).foregroundStyle(.red) }
            Rectangle().fill(colors.separator).frame(height: 0.5).padding(.horizontal, -20)
            HStack {
                Spacer()
                Button("Cancel", action: close).buttonStyle(ModalButtonStyle(colors: colors)).keyboardShortcut(.cancelAction)
                Button(clearing ? "Clearing…" : "Clear") { Task { await clear() } }
                    .buttonStyle(ModalButtonStyle(colors: colors, primary: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(clearing || request.isEmpty)
            }
        }
        .toggleStyle(.checkbox)
        .modalCard(colors, width: 420)
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .onExitCommand(perform: close)
    }

    private func option(_ title: String, detail: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13)).foregroundStyle(state.palette.text)
                Text(detail).font(.system(size: 11)).foregroundStyle(state.palette.secondary)
            }
            .padding(.leading, 2)
        }
        .disabled(clearing)
    }

    private func count(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        n == 0 ? "None" : "\(n) \(n == 1 ? one : many ?? one + "s")"
    }

    private func clear() async {
        clearing = true
        issue = await state.clearData(request)
        clearing = false
        if issue == nil { close() }
    }
}
