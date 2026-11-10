import Foundation

/// Installs extensions from the Chrome Web Store: downloads the package (CRX) from Google's
/// public update service, strips the CRX header to get the ZIP inside, and unpacks it with
/// macOS's `ditto`. Also installs local .crx/.zip files and unpacked folders.
enum WebStoreInstaller {
    /// "https://chromewebstore.google.com/detail/<slug>/<id>" → "<id>".
    static func extensionID(fromStoreURL string: String) -> String? {
        guard let url = URL(string: string), let host = url.host?.lowercased(),
              host == "chromewebstore.google.com" || host == "chrome.google.com" else { return nil }
        return url.pathComponents.last { isValidID($0) }
    }

    /// Chrome IDs are 32 letters a–p.
    static func isValidID(_ id: String) -> Bool {
        id.count == 32 && id.allSatisfy { ("a"..."p").contains($0) }
    }

    /// Downloads and unpacks `id`; returns the unpacked folder (in a temporary location).
    /// No cookies or disk cache: the store needs neither, and both would land outside protected storage.
    private static let downloads = URLSession(configuration: .ephemeral)

    static func download(id: String) async throws -> URL {
        guard isValidID(id) else { throw ExtensionManager.error("Not a Chrome Web Store extension ID") }
        var components = URLComponents(string: "https://clients2.google.com/service/update2/crx")!
        components.queryItems = [
            URLQueryItem(name: "response", value: "redirect"),
            URLQueryItem(name: "prodversion", value: "141.0.0.0"),
            URLQueryItem(name: "acceptformat", value: "crx3"),
            URLQueryItem(name: "x", value: "id=\(id)&uc"),
        ]
        let (data, response) = try await downloads.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            throw ExtensionManager.error("The Chrome Web Store didn't return this extension")
        }
        // Store packages must carry the store's signature; local packages the person picks are their own choice.
        return try unpack(packageData: CRXVerifier.verifiedArchive(data, id: id))
    }

    /// Unpacks a .crx or .zip package into a fresh temporary folder.
    static func unpack(packageData data: Data) throws -> URL {
        let zip = try zipPayload(of: data)
        let work = FileManager.default.temporaryDirectory.appending(path: "ikago-ext-\(UUID().uuidString)")
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: work) } }
        let archive = work.appending(path: "package.zip")
        let folder = work.appending(path: "unpacked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try zip.write(to: archive)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, folder.path]
        try ditto.run()
        ditto.waitUntilExit()
        try? FileManager.default.removeItem(at: archive)
        guard ditto.terminationStatus == 0,
              FileManager.default.fileExists(atPath: folder.appending(path: "manifest.json").path) else {
            throw ExtensionManager.error("The extension package couldn't be unpacked")
        }
        // Chrome-only signing metadata; WebKit doesn't use it.
        try? FileManager.default.removeItem(at: folder.appending(path: "_metadata"))
        succeeded = true
        return folder
    }

    /// CRX3: "Cr24", version 3, header length, header; CRX2: "Cr24", 2, key and signature
    /// lengths, key, signature. The ZIP follows. A plain ZIP is returned as is.
    static func zipPayload(of data: Data) throws -> Data {
        let bytes = [UInt8](data)
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return data }  // "PK\3\4"
        guard bytes.count > 16, bytes.starts(with: Array("Cr24".utf8)) else {
            throw ExtensionManager.error("Not an extension package")
        }
        let start: Int
        switch u32(4) {
        case 3: start = 12 + u32(8)
        case 2: start = 16 + u32(8) + u32(12)
        default: throw ExtensionManager.error("Unsupported extension package version")
        }
        guard start < bytes.count else { throw ExtensionManager.error("Damaged extension package") }
        return data.subdata(in: start..<bytes.count)
    }

    /// A stable ID for a local install: the folder or file name, hashed into Chrome's alphabet.
    static func localID(for source: URL) -> String {
        let letters = Array("abcdefghijklmnop")
        var hash: UInt64 = 1469598103934665603
        for byte in source.standardizedFileURL.path.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        var id = ""
        for i in 0..<32 { id.append(letters[Int((hash >> UInt64((i * 2) % 64)) & 0xF)]) }
        return id
    }
}
