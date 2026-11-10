import AppKit

/// Permission recovery uses the system file picker, never Full Disk Access or another process.
/// Apple: https://developer.apple.com/videos/play/wwdc2023/10053/ (19:13–20:38).
@MainActor
enum BrowserImportAccess {
    struct Grant {
        let directory: URL
        private let scoped: Bool
        init(directory: URL) {
            self.directory = directory
            scoped = directory.startAccessingSecurityScopedResource()
        }
        func end() { if scoped { directory.stopAccessingSecurityScopedResource() } }
    }

    static func prepare(_ source: DetectedBrowserProfile, force: Bool = false) async throws -> Grant? {
        guard source.kind != .file else { return nil }
        let blocked = await Task.detached { blockedResources(source) }.value
        guard force || !blocked.isEmpty else { return nil }
        let panel = NSOpenPanel()
        panel.title = "Allow \(source.browser) Import"
        panel.message = "Allow Ikago to read this \(source.browser) profile to import bookmarks, history, tabs, groups and available website logins. Click Allow Import to continue."
        panel.prompt = "Allow Import"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        // Opening the profile itself makes approval a single click without navigating Library.
        panel.directoryURL = source.directory
        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else {
                panel.begin { continuation.resume(returning: $0) }
            }
        }
        guard response == .OK, let selected = panel.url else { throw CancellationError() }
        let selectedPath = selected.standardizedFileURL.resolvingSymlinksInPath().path
        let targetPath = source.directory.standardizedFileURL.resolvingSymlinksInPath().path
        guard selectedPath == targetPath || targetPath.hasPrefix(selectedPath + "/") else {
            throw NSError(domain: "Ikago.ImportAccess", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Choose the detected \(source.browser) profile folder, \(source.directory.lastPathComponent), to allow this import."])
        }
        let grant = Grant(directory: selected)
        let remaining = await Task.detached { blockedResources(source) }.value
        guard remaining.isEmpty else {
            grant.end()
            throw CocoaError(.fileReadNoPermission)
        }
        return grant
    }

    /// Open handles only; do not read browsing records or request a Keychain key during discovery/preflight.
    nonisolated static func blockedResources(_ source: DetectedBrowserProfile) -> [String] {
        let files: [String], directories: [String]
        switch source.kind {
        case .chromium:
            files = ["Bookmarks", "History", "Cookies", "Network/Cookies", "Current Session"]
            directories = ["", "Sessions", "Network"]
        case .firefox:
            files = ["places.sqlite", "cookies.sqlite", "sessionstore.jsonlz4", "sessionstore-backups/recovery.jsonlz4", "sessionstore-backups/previous.jsonlz4"]
            directories = ["", "sessionstore-backups"]
        case .safari: files = ["Bookmarks.plist", "History.db"]; directories = [""]
        case .file: return []
        }
        var blocked: [String] = []
        for file in files {
            do { let handle = try FileHandle(forReadingFrom: source.directory.appending(path: file)); try handle.close() }
            catch { if ImportAccessError.isPermissionDenied(error) { blocked.append(file) } }
        }
        for directory in directories {
            do { _ = try FileManager.default.contentsOfDirectory(at: directory.isEmpty ? source.directory : source.directory.appending(path: directory), includingPropertiesForKeys: nil) }
            catch { if ImportAccessError.isPermissionDenied(error) { blocked.append(directory.isEmpty ? "Profile" : directory) } }
        }
        return blocked
    }
}

/// Preserve actual access failures rather than interpreting every SQLite open error as a denial.
enum ImportAccessError {
    static func isPermissionDenied(_ error: Error) -> Bool {
        contains(error) { error in
            (error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError)
                || (error.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(error.code))
        }
    }
    static func isMissing(_ error: Error) -> Bool {
        contains(error) { error in
            (error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code))
                || (error.domain == NSPOSIXErrorDomain && [Int(ENOENT), Int(ENOTDIR)].contains(error.code))
        }
    }
    private static func contains(_ error: Error, predicate: (NSError) -> Bool) -> Bool {
        var current = error as NSError
        for _ in 0..<8 {
            if predicate(current) { return true }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
            current = underlying
        }
        return false
    }
}
