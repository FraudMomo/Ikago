import SwiftUI

/// Shown over a tab whose page failed to load (offline, DNS, TLS, …).
struct ErrorPageView: View {
    let url: String
    let message: String
    let isDark: Bool
    var title = "Can't open this page"
    var symbol = "wifi.exclamationmark"
    var retryTitle = "Try Again"
    /// A second, less prominent way forward (open over HTTP, continue past a warning).
    var secondaryTitle: String? = nil
    var onSecondary: (() -> Void)? = nil
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.semibold))
            Text(AddressResolver.hostname(url).isEmpty ? url : AddressResolver.hostname(url))
                .font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            Button(retryTitle, action: onRetry).keyboardShortcut("r").controlSize(.large).padding(.top, 6)
            if let secondaryTitle, let onSecondary {
                Button(secondaryTitle, action: onSecondary).buttonStyle(.link).font(.callout)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDark ? Color(hex: 0x1e2427) : .white)
        .environment(\.colorScheme, isDark ? .dark : .light)
    }
}
