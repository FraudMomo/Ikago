import AppKit
import SwiftUI

// MARK: - Settings design

/// A rounded, colored icon, as in System Settings' sidebar.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.12), tint], startPoint: .top, endPoint: .bottom))
            .overlay { Image(systemName: symbol).font(.system(size: size * 0.55, weight: .medium)).foregroundStyle(.white) }
            .frame(width: size, height: size)
    }
}

/// A quiet visual cue beside Settings category titles; Appearance previews the browser chrome itself.
struct SettingsCategoryArtwork: View {
    let category: SettingsCategory
    let colors: Palette

    var body: some View {
        Group {
            if category == .appearance {
                HStack(spacing: 3) {
                    VStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule().fill(colors.secondary.opacity(0.35)).frame(height: 3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(5).frame(width: 19)
                    RoundedRectangle(cornerRadius: 3).fill(colors.pageBackground)
                        .overlay(alignment: .top) {
                            Capsule().fill(colors.selected).frame(height: 4).padding(.horizontal, 5).padding(.top, 5)
                        }
                        .padding(3)
                }
                .frame(width: 58, height: 38)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(colors.tint))
                .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(colors.separator, lineWidth: 1))
            } else {
                Image(systemName: category.symbol)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(colors.secondary)
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.primary.opacity(0.045)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A small status capsule.
struct StatusPill: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8).frame(height: 20)
        .foregroundStyle(tint)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

extension SettingsCategory {
    var tint: Color {
        switch self {
        case .general: Color(hex: 0x64748B)
        case .appearance: Color(hex: 0xEC4899)
        case .toolbar: Color(hex: 0x14B8A6)
        case .tabs: Color(hex: 0x6366F1)
        case .search: Color(hex: 0x3B82F6)
        case .extensions: Color(hex: 0x8B5CF6)
        case .history: Color(hex: 0xF59E0B)
        case .performance: Color(hex: 0x10B981)
        case .security: Color(hex: 0x22A559)
        case .passwords: Color(hex: 0x8E8E93)
        case .autofill: Color(hex: 0x5E5CE6)
        case .agents: Color(hex: 0x7C3AED)
        case .imports: Color(hex: 0x06A5C9)
        case .about: Color(hex: 0x71717A)
        }
    }
}

enum AppRelaunch {
    /// Quits normally so the session saves, then opens Ikago again once this process has gone.
    @MainActor
    static func relaunch(_ application: URL = Bundle.main.bundleURL) {
        let path = application.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"", "sh",
                             String(ProcessInfo.processInfo.processIdentifier), path]
        try? process.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Category header

/// The page's title and one short line, set like a document heading: no artwork, no banner.
struct SettingsCategoryHeader: View {
    let category: SettingsCategory
    let colors: Palette
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category.title).font(.system(size: 24, weight: .semibold)).tracking(-0.4)
            Text(category.detail).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsCategory {
    var detail: String {
        switch self {
        case .general: "Your engine and everyday tools"
        case .appearance: "Shape your browsing space"
        case .toolbar: "Keep useful controls within reach"
        case .tabs: "Opening and organizing tabs"
        case .search: "Search and address suggestions"
        case .extensions: "Manage what runs in your browser"
        case .history: "Pages you’ve visited, and clearing browsing data"
        case .performance: "Memory, sleeping tabs and what Ikago is using"
        case .security: "Connections, permissions and browsing data"
        case .passwords: "Sign in with your preferred password source"
        case .autofill: "Addresses and cards for forms"
        case .agents: "Let AI agents browse for you, where you can see them"
        case .imports: "Bring your data in, or take it with you"
        case .about: "Version, updates and developer tools"
        }
    }
}

extension EnvironmentValues {
    @Entry var settingsSurface = false
}
