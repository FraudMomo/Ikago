import SwiftUI

/// "Save password?" after a sign-in: the site, an editable username, and Save, Not Now or Never for this site.
struct PasswordSaveCard: View {
    let offer: PasswordSaveOffer
    let colors: Palette
    @State private var error: String?
    private var presenter: PasswordSavePresenter { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(LinearGradient(colors: [colors.accent.opacity(0.85), colors.accent], startPoint: .top, endPoint: .bottom)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(offer.update ? "Update saved password?" : "Save password?").font(.system(size: 13, weight: .semibold))
                    Text(offer.site).font(.system(size: 11)).foregroundStyle(colors.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                ChromeButton(symbol: "xmark", help: "Not Now", colors: colors, size: 22, glass: false) { presenter.dismiss() }
            }
            VStack(spacing: 0) {
                field("Username") {
                    TextField("Username", text: Binding(get: { offer.username }, set: { presenter.setUsername($0) }))
                        .textFieldStyle(.plain).font(.system(size: 12))
                }
                Rectangle().fill(colors.separator).frame(height: 0.5).padding(.leading, 10)
                field("Password") {
                    Text(String(repeating: "•", count: 10)).font(.system(size: 12)).foregroundStyle(colors.secondary)
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(colors.hover))
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 8) {
                if !offer.update {
                    Button("Never for This Site") { presenter.never() }.buttonStyle(.plain)
                        .font(.system(size: 11.5)).foregroundStyle(colors.secondary)
                }
                Spacer()
                Button("Not Now") { presenter.dismiss() }.buttonStyle(SettingsButtonStyle())
                Button(offer.update ? "Update" : "Save") { error = presenter.save() }
                    .buttonStyle(SettingsButtonStyle(prominent: true))
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
        .foregroundStyle(colors.text)
        .modalSurface(colors, radius: Radius.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(offer.update ? "Update saved password for \(offer.site)" : "Save password for \(offer.site)")
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 11)).foregroundStyle(colors.secondary).frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).frame(height: 30)
    }
}
