import AppKit
import SwiftUI

/// The update card at the top right of the frontmost window (`AppUpdateDriver`): what the update is about (a security
/// update with its Chromium, new features from BUILDS.md, or both), then Update and Relaunch or Later. The same card
/// shows the download, the install, and the answer to Ikago ▸ Check for Updates….
struct UpdateCard: View {
    let prompt: UpdatePrompt
    let phase: UpdatePrompt.Phase
    let colors: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    if let summary, case .found = phase { KindLabel(summary: summary, colors: colors) }
                    else if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(colors.secondary) }
                }
                Spacer(minLength: 4)
                ChromeButton(symbol: "xmark", help: "Later", colors: colors, size: 22, glass: false) { prompt.later() }
            }
            if case .found(let summary, _) = phase, !summary.notes.isEmpty { notes(summary) }
            if case .downloading(_, let fraction) = phase {
                ProgressView(value: fraction ?? 0).progressViewStyle(.linear).opacity(fraction == nil ? 0.4 : 1)
            }
            if case .installing = phase { ProgressView().progressViewStyle(.linear) }
            buttons
        }
        .padding(14)
        .frame(width: 380)
        .foregroundStyle(colors.text)
        .modalSurface(colors, radius: Radius.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .task(id: isUpToDate) {
            // "Up to date" answers a check the person asked for, then goes by itself.
            guard isUpToDate else { return }
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.ikago) { prompt.later() }
        }
    }

    private var summary: UpdateSummary? {
        switch phase {
        case .found(let summary, _): summary
        case .downloading(let summary, _), .installing(let summary): summary
        default: nil
        }
    }

    private var isUpToDate: Bool { if case .upToDate = phase { true } else { false } }

    private var title: String {
        let version = summary.map { "Ikago \($0.version)" } ?? "the update"
        switch phase {
        case .checking: return "Checking for updates…"
        case .found(let found, _) where found.downloadPage != nil: return "\(version) needs a new download"
        case .found(_, let downloaded): return downloaded ? "\(version) is ready to install" : "\(version) is available"
        case .downloading: return "Downloading \(version)…"
        case .installing: return "Installing \(version)…"
        case .upToDate: return "Ikago is up to date"
        case .failed: return "Ikago couldn’t check for updates"
        }
    }

    private var detail: String? {
        switch phase {
        case .checking: "Looking for a newer release"
        case .downloading, .installing: "Signed by Ikago and checked before it installs"
        case .upToDate: "You have the latest version, \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
        case .failed(let message): message
        case .found: nil
        }
    }

    private func notes(_ summary: UpdateSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(summary.notes.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle().fill(colors.tertiary).frame(width: 4, height: 4).offset(y: -2)
                        Text((try? AttributedString(markdown: line)) ?? AttributedString(line))
                            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 180)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(colors.hover))
    }

    @ViewBuilder private var buttons: some View {
        switch phase {
        case .found(let summary, _) where summary.downloadPage != nil:
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Later") { withAnimation(.ikago) { prompt.later() } }.buttonStyle(SettingsButtonStyle()).fixedSize()
                Button("Download from GitHub") { if let page = summary.downloadPage { prompt.download(page) } }
                    .buttonStyle(SettingsButtonStyle(prominent: true)).fixedSize()
            }
            .controlSize(.small)
        case .found(let summary, let downloaded):
            HStack(spacing: 8) {
                if !summary.security {
                    Button("Skip This Version") { prompt.skip() }.buttonStyle(.plain).font(.system(size: 11.5))
                        .foregroundStyle(colors.secondary)
                }
                Spacer(minLength: 0)
                Button("Later") { withAnimation(.ikago) { prompt.later() } }.buttonStyle(SettingsButtonStyle()).fixedSize()
                Button(downloaded ? "Relaunch to Update" : "Update and Relaunch") { prompt.install() }
                    .buttonStyle(SettingsButtonStyle(prominent: true)).fixedSize()
            }
            .controlSize(.small)
        case .checking, .downloading:
            HStack { Spacer(); Button("Cancel") { withAnimation(.ikago) { prompt.later() } }.buttonStyle(SettingsButtonStyle()).controlSize(.small) }
        case .failed:
            HStack { Spacer(); Button("OK") { withAnimation(.ikago) { prompt.later() } }.buttonStyle(SettingsButtonStyle(prominent: true)).controlSize(.small) }
        case .installing, .upToDate:
            EmptyView()
        }
    }
}

/// "Security update · Chromium 156.0.8078.96", or "New in Ikago".
private struct KindLabel: View {
    let summary: UpdateSummary
    let colors: Palette

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: summary.security ? "checkmark.shield.fill" : "sparkles")
                .foregroundStyle(summary.security ? Color.green : colors.accent)
            Text(summary.kind).foregroundStyle(colors.text.opacity(0.85))
            if let chromium = summary.chromium, summary.security {
                Text("· Chromium \(chromium)").foregroundStyle(colors.secondary)
            }
        }
        .font(.system(size: 11, weight: .medium))
    }
}
