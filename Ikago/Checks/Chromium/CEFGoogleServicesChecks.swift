import Foundation
import Darwin

@MainActor
enum CEFGoogleServicesChecks {
    static func run() throws {
        let directory = CEFSessions.root.appending(path: "KeyConfigFixture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "key")
        let fixture = "fixture-token-never-sent-to-google"
        try Data(fixture.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        guard try CEFGoogleServices.readKey(at: file) == fixture else { throw CEFError.script("Owner-only service configuration could not be read.") }
        func rejected(_ file: URL) throws {
            var failed = false
            do { _ = try CEFGoogleServices.readKey(at: file) } catch { failed = true }
            guard failed else { throw CEFError.script("Unsafe service configuration was accepted.") }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try rejected(file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let link = directory.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        try rejected(link)
        let pipe = directory.appending(path: "pipe")
        guard mkfifo(pipe.path, 0o600) == 0 else { throw CEFError.script("Could not create configuration FIFO fixture.") }
        try rejected(pipe)
        try Data(repeating: 65, count: 513).write(to: file)
        try rejected(file)
        print("CEF_GOOGLE_CONFIG_OK owner-only symlink-rejected fifo-rejected bounded-size no-environment-mutation")
    }
}
