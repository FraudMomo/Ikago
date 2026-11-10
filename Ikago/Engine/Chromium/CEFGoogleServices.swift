import Foundation
import Darwin

/// Configure Google's native Chromium client before loading the CEF framework.
/// Keys never enter session/preferences data, command-line arguments or logs.
@MainActor
enum CEFGoogleServices {
    private(set) static var configured = false
    static func prepare() throws {
        if let key = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"], !key.isEmpty {
            try validate(key); configured = true; return
        }
        // Fixtures may use an explicitly supplied environment key, but never
        // read the normal application's credentials or configuration file.
        guard CEFSessions.overrideRoot == nil else { return }
        let file = SessionStore.standard.directory.appending(path: "google-api-key")
        guard let key = try readKey(at: file) else { return }
        guard setenv("GOOGLE_API_KEY", key, 1) == 0 else { throw ConfigurationError("Google service configuration could not be applied.") }
        configured = true
    }
    static func readKey(at file: URL) throws -> String? {
        let descriptor = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw ConfigurationError("The Google API key file could not be opened safely.")
        }
        return try readKey(descriptor: descriptor)
    }
    private static func readKey(descriptor: Int32) throws -> String {
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG, information.st_uid == geteuid(),
              information.st_mode & 0o077 == 0, information.st_size > 0, information.st_size <= 512 else {
            throw ConfigurationError("The Google API key file must be an owner-only regular file (0600), owned by you, and at most 512 bytes.")
        }
        guard let data = try handle.read(upToCount: 513), data.count <= 512,
              let value = String(data: data, encoding: .utf8) else { throw ConfigurationError("The Google API key file is not valid UTF-8.") }
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try validate(key)
        return key
    }
    private static func validate(_ key: String) throws {
        guard !key.isEmpty, key.utf8.count <= 512,
              key.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else {
            throw ConfigurationError("The Google API key must be a single non-empty ASCII token.")
        }
    }
    private struct ConfigurationError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
