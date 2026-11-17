import SwiftUI

@MainActor
@Observable
final class FindBarModel {
    var text = ""
    var matchCount = 0
    var activeMatch = 0
    /// Every match on the page, when Highlight All counted them (WebKit); nil otherwise.
    var totalMatches: Int?
    /// Highlight All is offered (WebKit; Chromium always marks every match).
    var offersHighlightAll = true
    var highlightAll = UserDefaults.standard.object(forKey: "findHighlightAll") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(highlightAll, forKey: "findHighlightAll")
            if !highlightAll { totalMatches = nil }
            onHighlightAllChanged()
        }
    }
    @ObservationIgnored var onHighlightAllChanged: () -> Void = {}
    @ObservationIgnored var onSearch: (_ text: String, _ forward: Bool, _ findNext: Bool) -> Void = { _, _, _ in }
    @ObservationIgnored var onClose: () -> Void = {}

    func search(forward: Bool = true, next: Bool = false) {
        guard !text.isEmpty else {
            matchCount = 0
            activeMatch = 0
            totalMatches = nil
            onSearch(text, forward, next)  // clears Highlight All marks
            return
        }
        onSearch(text, forward, next)
    }
}

/// ⌘F find-in-page: a card floating over the top-right of the page, in the Space's colors like the other floating
/// surfaces: the field, the match count, Highlight All, then Previous/Next in one glass group and Close.
struct FindBarView: View {
    @Bindable var model: FindBarModel
    let colors: Palette
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(colors.secondary)
                TextField("Find in page", text: $model.text)
                    .textFieldStyle(.plain)
                    .foregroundStyle(colors.text)
                    .focused($focused)
                    .frame(width: 170)
                    .onChange(of: model.text) { model.search() }
                    .onSubmit { model.search(forward: !NSEvent.modifierFlags.contains(.shift), next: true) }
                    .onKeyPress(.escape) { model.onClose(); return .handled }
                status
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(colors.selected.opacity(0.6)))

            if model.offersHighlightAll { highlightToggle }

            GlassControlGroup(colors: colors, height: 30) {
                HStack(spacing: 0) {
                    ChromeButton(symbol: "chevron.up", help: "Previous (⇧↩)", colors: colors, size: 26, iconSize: 11,
                                 enabled: !model.text.isEmpty) { model.search(forward: false, next: true) }
                    ChromeButton(symbol: "chevron.down", help: "Next (↩)", colors: colors, size: 26, iconSize: 11,
                                 enabled: !model.text.isEmpty) { model.search(forward: true, next: true) }
                }
            }
            ChromeButton(symbol: "xmark", help: "Close (Esc)", colors: colors, size: 26, iconSize: 10) { model.onClose() }
        }
        .font(.system(size: 13))
        .padding(.leading, 8).padding(.trailing, 7)
        .frame(height: 44)
        .surface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous), colors)
        .fixedSize()
        .animation(.ikagoQuick, value: model.matchCount)
        .animation(.ikagoQuick, value: model.totalMatches)
        .onAppear { focused = true }
    }

    /// "Not found" or the match count, small and secondary at the end of the field.
    @ViewBuilder private var status: some View {
        if !model.text.isEmpty && model.matchCount == 0 {
            Text("Not found").font(.system(size: 11)).foregroundStyle(colors.secondary).fixedSize().transition(.opacity)
        } else if !model.text.isEmpty, let total = model.totalMatches, total > 0 {
            Text(total == 1 ? "1 match" : "\(total) matches").font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(colors.secondary).fixedSize().transition(.opacity)
        }
    }

    /// Highlight All as a labeled pill: filled while on, like a selected row.
    private var highlightToggle: some View {
        Button { model.highlightAll.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "highlighter").font(.system(size: 11, weight: .medium))
                Text("Highlight All").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(model.highlightAll ? colors.text : colors.secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(model.highlightAll ? colors.selected : .clear))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(colors.separator, lineWidth: model.highlightAll ? 0 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(model.highlightAll ? "Highlight All matches: On" : "Highlight All matches: Off")
        .animation(.ikagoQuick, value: model.highlightAll)
    }
}
