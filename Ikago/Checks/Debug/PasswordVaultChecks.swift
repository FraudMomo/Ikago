#if DEBUG
import Foundation

/// Ikago's password vault and importing into it, on a disposable folder with a software key.
@MainActor
enum PasswordVaultChecks {
    static func run(check: (Bool, String) -> Void) async {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appending(path: "ikago-vault-\(UUID().uuidString)")
        defer { try? files.removeItem(at: directory) }
        let vault = PasswordVault(directory: directory, usesTestKey: true)
        let added = try? vault.add([
            .init(url: "https://www.Example.com/login", title: "Example", username: "ana@example.com", password: "correct horse 1"),
            .init(url: "https://accounts.example.com", title: nil, username: "ana", password: "second secret 2"),
            .init(url: "https://other.test", title: nil, username: "bo", password: "third secret 3"),
            .init(url: "https://alice.github.io", title: nil, username: "alice", password: "fourth secret 4"),
            .init(url: "https://mail.example.com", title: nil, username: "cy", password: "fifth secret 5"),
        ])
        check(added == 5, "logins are added to the vault")
        check(PublicSuffix.isAvailable, "the public suffix list is bundled")
        check(PublicSuffix.registrableDomain("a.b.example.co.uk") == "example.co.uk" && PublicSuffix.registrableDomain("alice.github.io") == "alice.github.io"
              && PublicSuffix.registrableDomain("github.io") == "github.io" && PublicSuffix.registrableDomain("127.0.0.1") == "127.0.0.1",
              "registrable domains follow the public suffix list")
        let raw = (try? Data(contentsOf: directory.appending(path: "passwords.vault"))) ?? Data()
        check(!raw.isEmpty && !["correct horse", "ana@example.com", "example.com", "other.test"].contains { raw.range(of: Data($0.utf8)) != nil },
              "the vault file hides passwords, usernames and sites")
        let reopened = PasswordVault(directory: directory, usesTestKey: true)
        let matches = reopened.matches(for: "login.example.com")
        let all = reopened.matches(for: "example.com")
        // The whole registrable domain, parents and children before other subdomains.
        check(matches.map(\.username) == ["ana@example.com", "ana", "cy"] || matches.map(\.username) == ["ana@example.com", "cy", "ana"],
              "a site's logins include its parent domain first, then other subdomains of the same site")
        check(matches.first?.username == "ana@example.com", "the parent domain's login comes before siblings")
        check(Set(reopened.matches(for: "example.com").map(\.username)) == ["ana@example.com", "ana", "cy"], "a site's logins include its subdomains")
        check(reopened.matches(for: "accounts.example.com").first?.username == "ana", "the exact host comes first")
        check(reopened.matches(for: "bob.github.io").isEmpty && reopened.matches(for: "github.io").isEmpty,
              "subdomains of a public suffix are separate sites")
        check(reopened.matches(for: "example.com.evil.test").isEmpty && reopened.matches(for: "notexample.com").isEmpty,
              "look-alike hosts get no logins")
        if let login = all.first(where: { $0.username == "ana@example.com" }) {
            let password = try? await reopened.password(for: login, reason: "check")
            check(password == "correct horse 1", "a password decrypts for its login")
        } else { check(false, "a password decrypts for its login") }
        _ = try? reopened.add([.init(url: "https://example.com", title: nil, username: "ana@example.com", password: "changed 4")])
        let replaced = reopened.matches(for: "example.com").filter { $0.username == "ana@example.com" }
        check(replaced.count == 1, "importing the same login again replaces it")
        if let login = replaced.first { check((try? await reopened.password(for: login, reason: "check")) == "changed 4", "the replaced password is the new one") }

        // A password moved to another site's entry doesn't decrypt there.
        if var forged = reopened.matches(for: "other.test").first, let donor = reopened.matches(for: "example.com").first {
            forged.secret = donor.secret
            let swapped = PasswordVault(directory: directory, usesTestKey: true)
            check((try? await swapped.password(for: forged, reason: "check")) != "changed 4", "a password copied onto another site's login is refused")
        }
        if let first = reopened.matches(for: "other.test").first { try? reopened.delete([first.id]) }
        check(PasswordVault(directory: directory, usesTestKey: true).matches(for: "other.test").isEmpty, "deleting a login removes it")
        try? reopened.deleteAll()
        check(!files.fileExists(atPath: directory.appending(path: "passwords.vault").path)
              && !files.fileExists(atPath: directory.appending(path: "passwords.backup.vault").path), "deleting all removes the vault and its backup")

        // Apple's and Chrome's export formats, quoting included.
        let apple = "Title,URL,Username,Password,Notes,OTPAuth\r\nExample,https://example.com/,ana,\"pa,ss\"\"word\",\"line one\nline two\",\r\nWi-Fi,,,netpass,,\r\n"
        let parsed = try? PasswordImport.parse("\u{FEFF}" + apple)
        check(parsed?.logins == [.init(url: "https://example.com/", title: "Example", username: "ana", password: "pa,ss\"word")] && parsed?.skipped == 1,
              "Apple Passwords exports import, quotes and notes included")
        let chrome = try? PasswordImport.parse("name,url,username,password,note\nsite,https://site.test/login,bo,secret,\n")
        check(chrome?.logins.first?.username == "bo" && chrome?.logins.first?.password == "secret", "Chrome exports import")
        check((try? PasswordImport.parse("a,b\n1,2\n")) == nil, "files that aren't password exports are refused")
        let export = directory.appending(path: "export.csv")
        try? files.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(apple.utf8).write(to: export)
        try? PasswordImport.erase(export)
        check(!files.fileExists(atPath: export.path), "the exported file is erased after importing")
        // Erasing never writes through a link into the file it points to.
        let target = directory.appending(path: "important.txt"), link = directory.appending(path: "link.csv")
        try? Data("keep me".utf8).write(to: target)
        try? files.createSymbolicLink(at: link, withDestinationURL: target)
        check((try? PasswordImport.erase(link)) == nil && (try? String(contentsOf: target, encoding: .utf8)) == "keep me",
              "erasing refuses a link and leaves its target alone")

        // A vault file that can't be opened is never saved over with a new key.
        let damaged = directory.appending(path: "damaged")
        try? files.createDirectory(at: damaged, withIntermediateDirectories: true)
        let garbage = Data("not a vault".utf8)
        try? garbage.write(to: damaged.appending(path: "passwords.vault"))
        let unreadable = PasswordVault(directory: damaged, usesTestKey: true)
        let refused = (try? unreadable.add([.init(url: "https://new.test", title: nil, username: "x", password: "y")])) == nil
        check(refused && unreadable.loadIssue != nil && (try? Data(contentsOf: damaged.appending(path: "passwords.vault"))) == garbage,
              "an unreadable vault refuses changes and stays as it was")

        check(PasswordChooser.origin(of: URL(string: "https://Example.com:443/a")!) == "https://example.com"
              && PasswordChooser.origin(of: URL(string: "http://127.0.0.1:8080/")!) == "http://127.0.0.1:8080"
              && PasswordChooser.origin(of: URL(string: "http://[::1]:3000/")!) == "http://[::1]:3000", "fill origins match location.origin")
    }
}
#endif
