import Foundation

/// Reads a passwords file exported from Apple's Passwords app (File ▸ Export All Passwords…) or from
/// Chrome, then erases it. Apple: Title,URL,Username,Password,Notes,OTPAuth. Chrome: name,url,username,
/// password,note. Columns are found by name, so their order doesn't matter.
enum PasswordImport {
    struct Result: Equatable {
        var logins: [PasswordVault.NewLogin]
        /// Rows without a web address or password, such as Wi-Fi networks or app-only logins.
        var skipped: Int
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static func parse(_ text: String) throws -> Result {
        var rows = csvRows(text)
        guard let header = rows.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }) else {
            throw Failure(errorDescription: "The file is empty.")
        }
        rows.removeFirst()
        func column(_ names: String...) -> Int? { header.firstIndex { names.contains($0) } }
        guard let url = column("url", "website", "login_uri"), let password = column("password", "login_password") else {
            throw Failure(errorDescription: "This doesn’t look like a passwords export: it has no URL and Password columns.")
        }
        let username = column("username", "login_username", "user name")
        let title = column("title", "name")
        var logins: [PasswordVault.NewLogin] = [], skipped = 0
        for row in rows where !(row.count == 1 && row[0].isEmpty) {
            func value(_ index: Int?) -> String { index.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            let address = value(url).trimmingCharacters(in: .whitespaces)
            let secret = value(password)
            guard let parsed = URL(string: address.contains("://") ? address : "https://" + address),
                  let scheme = parsed.scheme?.lowercased(), scheme == "https" || scheme == "http",
                  parsed.host?.isEmpty == false, !secret.isEmpty else { skipped += 1; continue }
            logins.append(.init(url: parsed.absoluteString, title: value(title).isEmpty ? nil : value(title),
                                username: value(username), password: secret))
        }
        return Result(logins: logins, skipped: skipped)
    }

    /// RFC 4180: commas, quoted fields with "" escapes, and line breaks inside quotes (notes).
    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        var characters = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)[...]
        while let character = characters.popFirst() {
            if quoted {
                if character == "\"" {
                    if characters.first == "\"" { field.append("\""); characters.removeFirst() } else { quoted = false }
                } else { field.append(character) }
                continue
            }
            switch character {
            case "\"": quoted = true
            case ",": row.append(field); field = ""
            case "\n", "\r\n", "\r":
                row.append(field); field = ""
                rows.append(row); row = []
            default: field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    /// Overwrites the file's bytes, then deletes it, so a plain copy doesn't linger on disk or in the
    /// Trash. APFS and SSDs may keep old blocks until they're reused; FileVault keeps those encrypted.
    static func erase(_ url: URL) throws {
        // Never write through a link: the zeros would land in whatever file it points to.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw Failure(errorDescription: "The exported file isn’t a regular file, so it wasn’t erased.")
        }
        let handle = try FileHandle(forUpdating: url)
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        var remaining = size
        let zeros = Data(count: 64 * 1024)
        while remaining > 0 {
            let chunk = Int(min(UInt64(zeros.count), remaining))
            try handle.write(contentsOf: zeros.prefix(chunk))
            remaining -= UInt64(chunk)
        }
        try handle.synchronize()
        try handle.close()
        try FileManager.default.removeItem(at: url)
    }
}
