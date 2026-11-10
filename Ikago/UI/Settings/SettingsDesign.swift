import AppKit
import SwiftUI

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
        case .search: Color(hex: 0x3B82F6)
        case .tabs: Color(hex: 0x6366F1)
        case .appearance: Color(hex: 0xEC4899)
        case .toolbar: Color(hex: 0x14B8A6)
        case .extensions: Color(hex: 0x8B5CF6)
        case .security: Color(hex: 0x22A559)
        case .passwords: Color(hex: 0x8E8E93)
        case .privacy: Color(hex: 0xF97316)
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
