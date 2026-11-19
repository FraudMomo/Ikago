import SwiftUI

/// The list of saved logins under a sign-in field: the site and a close button above, a search field when there are
/// many, one row per username (a chevron shows the other sites that share it), and Manage Passwords below.
struct PasswordSuggestionsView: View {
    let suggestions: PasswordSuggestions
    let colors: Palette
    private var presenter: PasswordSuggestionsPresenter { .shared }
    @State private var query = ""

    var body: some View {
        let rows = suggestions.rowList
        VStack(alignment: .leading, spacing: 0) {
            header
            if suggestions.searches { search }
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        switch row {
                        case .generated(let password): strongRow(password, index: index)
                        case .login(let login, let others): loginRow(login, others: others, index: index)
                        case .member(let login): memberRow(login, index: index)
                        }
                    }
                    if rows.isEmpty {
                        Text("No saved login matches “\(suggestions.query)”")
                            .font(.system(size: 12)).foregroundStyle(colors.secondary)
                            .frame(maxWidth: .infinity, minHeight: PasswordSuggestions.rowHeight)
                    }
                }
            }
            .scrollDisabled(rows.count <= PasswordSuggestions.visibleRows)
            .scrollIndicators(.automatic)
            Rectangle().fill(colors.separator).frame(height: 0.5).padding(.horizontal, 6).padding(.vertical, 4)
            Button { presenter.manage() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "key.horizontal").font(.system(size: 11)).frame(width: 18)
                    Text("Manage Passwords…").font(.system(size: 12))
                    Spacer()
                }
                .foregroundStyle(colors.secondary)
                .padding(.horizontal, 8)
                .frame(height: PasswordSuggestions.footerHeight - 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .modalSurface(colors, radius: Radius.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saved passwords for \(suggestions.site)")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(suggestions.site).font(.system(size: 12, weight: .semibold)).foregroundStyle(colors.text).lineLimit(1)
            Image(systemName: "touchid").font(.system(size: 11)).foregroundStyle(colors.tertiary)
                .help("Each fill asks for Touch ID or your Mac password")
            Spacer(minLength: 8)
            ChromeButton(symbol: "xmark", help: "Close", colors: colors, size: 20, iconSize: 9, glass: false) { presenter.dismiss() }
        }
        .padding(.leading, 8).padding(.trailing, 2)
        .frame(height: PasswordSuggestions.headerHeight)
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(colors.tertiary)
            TextField("Search logins", text: $query)
                .textFieldStyle(.plain).font(.system(size: 12))
                .onChange(of: query) { _, text in presenter.search(text) }
        }
        .padding(.horizontal, 8)
        .frame(height: PasswordSuggestions.searchHeight - 8)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(colors.hover.opacity(0.7)))
        .padding(.horizontal, 2).padding(.bottom, 8)
    }

    private func background(_ index: Int) -> some View {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(suggestions.selected == index ? colors.hover : .clear)
    }

    private func returnMark(_ index: Int) -> some View {
        Image(systemName: "return").font(.system(size: 10, weight: .semibold)).foregroundStyle(colors.tertiary)
            .opacity(suggestions.selected == index ? 1 : 0)
    }

    private func monogram(_ text: String, color: Color, size: CGFloat = 28) -> some View {
        Text(String(text.prefix(1)).uppercased())
            .font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(color)
            .frame(width: size, height: size)
            .background(Circle().fill(color.opacity(0.14)))
    }

    /// The strong password: what it is, and that it's saved only when the person confirms.
    private func strongRow(_ password: String, index: Int) -> some View {
        Button { presenter.choose(index) } label: {
            HStack(spacing: 10) {
                Image(systemName: "key.viewfinder").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.green)
                    .frame(width: 28, height: 28).background(Circle().fill(Color.green.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Use Strong Password").font(.system(size: 13, weight: .medium)).foregroundStyle(colors.text)
                    Text(password).font(.system(size: 11, design: .monospaced)).foregroundStyle(colors.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                returnMark(index)
            }
            .padding(.horizontal, 8)
            .frame(height: PasswordSuggestions.rowHeight)
            .background(background(index))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { presenter.select(index) } }
        .help("Fills this field and its confirmation; Ikago asks to save it once the form goes through")
        .accessibilityLabel("Use strong password")
    }

    private func loginRow(_ login: PasswordVault.Login, others: Int, index: Int) -> some View {
        let name = login.username.isEmpty ? "No username" : login.username
        let open = suggestions.expanded.contains(PasswordSuggestions.key(login.username))
        // A second line only when it says more than the header: a saved title, another subdomain, or more sites.
        let place = login.title?.isEmpty == false ? login.title : login.site != suggestions.site ? login.site : nil
        let detail = others > 0 ? [place, "\(others + 1) sites"].compactMap { $0 }.joined(separator: " · ") : place
        return HStack(spacing: 4) {
            Button { presenter.choose(index) } label: {
                HStack(spacing: 10) {
                    monogram(name, color: colors.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(colors.text).lineLimit(1).truncationMode(.middle)
                        if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(colors.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 4)
                    returnMark(index)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fill \(name)")
            if others > 0 {
                ChromeButton(symbol: open ? "chevron.up" : "chevron.down", help: open ? "Hide the other sites" : "Show every site with this username",
                             colors: colors, size: 22, iconSize: 9, glass: false) { presenter.toggle(login.username) }
            }
        }
        .padding(.leading, 8).padding(.trailing, others > 0 ? 3 : 8)
        .frame(height: PasswordSuggestions.rowHeight)
        .background(background(index))
        .onHover { inside in if inside { presenter.select(index) } }
    }

    /// Another site's login for the same username: indented under it, with its site.
    private func memberRow(_ login: PasswordVault.Login, index: Int) -> some View {
        Button { presenter.choose(index) } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(colors.tertiary)
                    .frame(width: 28)
                Text(login.site).font(.system(size: 12)).foregroundStyle(colors.text).lineLimit(1).truncationMode(.middle)
                if let title = login.title, !title.isEmpty {
                    Text(title).font(.system(size: 11)).foregroundStyle(colors.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                returnMark(index)
            }
            .padding(.horizontal, 8)
            .frame(height: PasswordSuggestions.memberHeight)
            .background(background(index))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { presenter.select(index) } }
        .accessibilityLabel("Fill \(login.username) for \(login.site)")
    }
}
