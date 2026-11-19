import SwiftUI

/// Save Page (⌘S, the site card's Save tile): what to make of the page, in three groups. Document: a web archive with
/// everything (opens offline), the HTML alone, or the text. PDF: printable pages, or one long page. Image: the whole page
/// or what is on screen, as PNG or JPEG. Save asks where; Copy puts images and text on the clipboard instead.
struct SavePageSheet: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    let close: () -> Void
    /// The last choice, for the next time this session.
    @MainActor private static var lastFormat: PageSaveFormat = .archive
    @State private var format = SavePageSheet.lastFormat
    @State private var busy: Busy?
    @State private var problem: String?
    @State private var copied = false

    private enum Busy { case saving, copying }

    private var engine: BrowserEngine { state.activeTab?.engine ?? BrowserRuntime.engine }

    var body: some View {
        let colors = state.palette
        VStack(alignment: .leading, spacing: 16) {
            header(colors)
            section("Document", colors: colors) {
                option(.archive, symbol: "archivebox.fill", tint: .green, detail: "Everything, opens offline", colors: colors)
                option(.html, symbol: "chevron.left.forwardslash.chevron.right", tint: .orange, detail: "The page’s markup", colors: colors)
                option(.text, symbol: "text.alignleft", tint: .gray, detail: "Just the words", colors: colors)
            }
            section("PDF", colors: colors) {
                option(.pdf, symbol: "doc.richtext.fill", tint: .red, detail: "Pages to print or share", colors: colors)
                option(.longPDF, symbol: "scroll.fill", tint: .pink, detail: "One continuous page", colors: colors)
            }
            section("Image", colors: colors) {
                option(format.isImage && !isVisible ? format : .fullPNG, symbol: "photo.fill", tint: .blue,
                       detail: "The whole page in one image", colors: colors)
                option(isVisible ? format : .visiblePNG, symbol: "rectangle.dashed", tint: .teal, detail: "What’s on screen", colors: colors)
            }
            if format.isImage {
                HStack(spacing: 10) {
                    Text("File type").font(.system(size: 12)).foregroundStyle(colors.secondary)
                    Picker("File type", selection: Binding(get: { format.isJPEG }, set: { format = format.withJPEG($0) })) {
                        Text("PNG").tag(false)
                        Text("JPEG").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 140)
                    Text(format.isJPEG ? "Smaller file" : "Sharpest").font(.system(size: 11)).foregroundStyle(colors.tertiary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            footer(colors)
        }
        .padding(20)
        .frame(width: 520)
        .modalSurface(colors, tint: 0.12)
        .foregroundStyle(colors.text)
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .onExitCommand(perform: close)
        .animation(.ikagoQuick, value: format)
        .animation(.ikagoQuick, value: problem)
    }

    private var isVisible: Bool { format == .visiblePNG || format == .visibleJPEG }

    private func header(_ colors: Palette) -> some View {
        HStack(spacing: 12) {
            Group {
                if let tab = state.activeTab { FaviconView(tab: tab, size: 18) } else { Image(systemName: "globe") }
            }
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.text.opacity(0.06)))
            VStack(alignment: .leading, spacing: 1) {
                Text("Save Page").font(.system(size: 15, weight: .semibold))
                Text(state.activeTab?.displayTitle ?? "").font(.system(size: 12)).foregroundStyle(colors.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            ModalCloseButton(colors: colors, action: close)
        }
    }

    private func section<Content: View>(_ title: String, colors: Palette, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SiteCardHeading(title: title, colors: colors)
            HStack(spacing: 8) { content() }
        }
    }

    private func option(_ choice: PageSaveFormat, symbol: String, tint: Color, detail: String, colors: Palette) -> some View {
        let selected = choice == format
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return Button { format = choice; problem = nil; copied = false } label: {
            VStack(alignment: .leading, spacing: 8) {
                SettingTile(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(choice.title(for: engine)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(detail).font(.system(size: 11)).foregroundStyle(colors.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .padding(10)
            .background(shape.fill(selected ? colors.accent.opacity(0.12) : colors.text.opacity(0.04)))
            .overlay(shape.strokeBorder(selected ? colors.accent : colors.text.opacity(0.08), lineWidth: selected ? 1.5 : 0.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func footer(_ colors: Palette) -> some View {
        HStack(spacing: 8) {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
                    .lineLimit(2).transition(.opacity)
            } else if copied {
                Label("Copied", systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            // Images, HTML and text can go straight to the clipboard; archives and PDFs only make sense as files.
            if format.isImage || format == .text || format == .html {
                Button { run(copy: true) } label: {
                    if busy == .copying { ProgressView().controlSize(.small) } else { Text("Copy") }
                }
                .controlSize(.large)
                .disabled(busy != nil)
            }
            Button { run(copy: false) } label: {
                if busy == .saving { ProgressView().controlSize(.small) } else { Text("Save…") }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(busy != nil)
        }
    }

    private func run(copy: Bool) {
        guard let commands else { return }
        Self.lastFormat = format
        problem = nil
        copied = false
        busy = copy ? .copying : .saving
        Task { @MainActor in
            defer { busy = nil }
            do {
                let done = try await commands.savePage(format, copy: copy)
                if copy { copied = true } else if done { close() }
            } catch {
                problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
