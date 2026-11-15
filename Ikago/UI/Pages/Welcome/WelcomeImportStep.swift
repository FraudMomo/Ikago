import SwiftUI

/// Optional welcome step: bring bookmarks, history, tabs and logins over from a browser already on this Mac.
struct WelcomeImportStep: View {
    let state: BrowserState
    private var model: BrowserImportModel { state.importer }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Bring your browsing").font(.system(size: 26, weight: .semibold))
                Text("Import bookmarks, history, tabs and logins. You can skip this and import later in Settings.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            list
            if let result = model.result {
                Text(result).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await model.refresh() }
    }

    @ViewBuilder private var list: some View {
        if model.discovering && model.profiles.isEmpty {
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Finding your browsers…").foregroundStyle(.secondary) }
                .padding(20)
        } else if model.profiles.isEmpty {
            Text("No other browsers found.").foregroundStyle(.secondary).padding(20)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.profiles) { profile in
                        HStack(spacing: 12) {
                            BrowserLogo(browser: profile.browser, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.title).font(.system(size: 14, weight: .medium))
                                Text(profile.subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            BrowserImportButton(state: state, profile: profile, prominent: false)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.primary.opacity(0.045)))
                    }
                }
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: model.profiles.count <= 4)
        }
    }
}
