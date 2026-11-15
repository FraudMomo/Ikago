import SwiftUI

/// Under an extension in Settings: which websites it may read (every website, or ask on each), the websites already
/// decided with a way to undo each, and what it can do, in plain words.
struct ExtensionAccessDetails: View {
    let ext: ExtensionDescriptor
    @Environment(\.pagePalette) private var palette
    private var access: ExtensionAccess { .shared }

    var body: some View {
        let entry = access.entry(ext.key)
        VStack(alignment: .leading, spacing: 12) {
            if !ext.patterns.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Website access").font(.system(size: 12.5, weight: .medium))
                        Text(entry.everySite ? "Runs on every website it asks for, without asking."
                                             : "Asks the first time you visit each website; nothing runs there until you allow it.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    CompactMenu(value: entry.everySite ? "Every Website" : "Ask on Each Website", choices: [
                        MenuChoice(title: "Ask on Each Website", isOn: !entry.everySite, symbol: "questionmark.circle") {
                            access.setEverySite(false, key: ext.key)
                        },
                        MenuChoice(title: "Every Website", isOn: entry.everySite, symbol: "globe") { access.setEverySite(true, key: ext.key) },
                    ])
                }
                let sites = entry.sites.keys.sorted()
                if !sites.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(sites.enumerated()), id: \.element) { index, site in
                            if index > 0 { Divider().padding(.leading, 10) }
                            HStack(spacing: 8) {
                                Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(.secondary)
                                Text(site).font(.system(size: 12)).lineLimit(1)
                                Spacer()
                                CompactMenu(value: ExtensionAccessMenu.label(access.status(ext.key, site: site)),
                                            choices: ExtensionAccessMenu.choices(ext, site: site))
                                Button { access.forget(site: site, key: ext.key) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain).foregroundStyle(.tertiary)
                                    .help("Forget the choice for \(site)").accessibilityLabel("Forget \(site)")
                            }
                            .padding(.horizontal, 10).frame(height: 34)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Color.primary.opacity(0.04)))
                }
            }
            if !ext.abilities.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("It can").font(.system(size: 12.5, weight: .medium))
                    ForEach(ext.abilities, id: \.self) { ability in
                        Label(ability, systemImage: "checkmark").font(.system(size: 11.5)).foregroundStyle(.secondary)
                            .labelStyle(AbilityLabelStyle())
                    }
                }
            }
        }
        .padding(.leading, 48).padding(.bottom, 12)
    }
}

private struct AbilityLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The disclosure button that shows `ExtensionAccessDetails`.
struct ExtensionDetailsButton: View {
    @Binding var expanded: Bool
    var body: some View {
        Button { withAnimation(.ikagoQuick) { expanded.toggle() } } label: {
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .help(expanded ? "Hide website access and permissions" : "Website access and permissions")
    }
}
