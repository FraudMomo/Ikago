import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DownloadRow: View {
    let item: DownloadCenter.Item
    let colors: Palette
    var center: DownloadCenter = .shared
    var compact = false
    var onOpen: (() -> Void)? = nil
    @State private var icon: NSImage?
    @State private var hovering = false
    @State private var openFailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Group {
                        if let icon { Image(nsImage: icon).resizable() }
                        else { Image(systemName: "doc").resizable().scaledToFit() }
                    }.frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
                        .overlay(alignment: .bottomTrailing) {
                            if item.finished {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white, colors.accent)
                                    .offset(x: 4, y: 3).transition(.opacity)
                            }
                        }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.name).font(.system(size: 13, weight: .medium)).foregroundStyle(colors.text).lineLimit(1)
                        if item.inProgress {
                            ProgressView(value: item.total > 0 ? item.fraction : nil).controlSize(.small).tint(colors.accent)
                                .accessibilityLabel("Download progress for \(item.name)")
                        }
                        Text(status).font(.system(size: 11)).monospacedDigit()
                            .foregroundStyle(item.failed || item.interrupted ? Color.orange : colors.secondary).lineLimit(1)
                        if !compact {
                            Text(item.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(colors.tertiary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 12).padding(.leading, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!item.finished)
            .accessibilityLabel(item.finished ? "Open \(item.name)" : item.name)
            .help(item.finished ? "Open \(item.name)" : item.errorDescription ?? status)
            if item.inProgress {
                ChromeButton(symbol: "xmark", help: "Cancel Download", colors: colors, size: 26, glass: false) { center.cancel(item.id) }
                    .accessibilityLabel("Cancel \(item.name)")
            } else if item.finished {
                ChromeButton(symbol: "magnifyingglass", help: "Show in Finder", colors: colors, size: 26, glass: false) { center.reveal(item) }
                    .accessibilityLabel("Show \(item.name) in Finder")
            }
        }
        .padding(.trailing, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? colors.hover : .clear))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .ikagoQuick, value: hovering)
        .animation(reduceMotion ? nil : .ikago, value: item.finished)
        .contextMenu {
            if item.finished {
                Button("Open", action: open)
                Button("Show in Finder") { center.reveal(item) }
            }
            if !item.inProgress { Button("Remove from History") { center.remove(item.id) } }
        }
        .alert("Couldn’t Open Download", isPresented: $openFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("The file may have been moved or deleted, or no app is available to open it.") }
        .task(id: item.name) {
            icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data)
        }
    }

    private func open() { if center.open(item) { onOpen?() } else { openFailed = true } }

    private var status: String {
        if item.cancelled { return "Cancelled" }
        if item.interrupted { return "Interrupted · \(size(item.received)) received" }
        if item.failed { return "Failed · \(size(item.received)) received" }
        if item.finished { return size(item.received) }
        return item.total > 0 ? "\(size(item.received)) of \(size(item.total)) · \(Int(item.fraction * 100))%" : "\(size(item.received)) received"
    }
    private func size(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
}
