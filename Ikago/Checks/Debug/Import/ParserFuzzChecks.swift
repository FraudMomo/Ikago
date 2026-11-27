#if DEBUG
import Compression
import CryptoKit
import Foundation

/// Every parser of data Ikago didn't write: other browsers' files, export archives, extension packages. A damaged
/// or hostile file must throw or yield less, never trap and end Ikago. Each parser gets valid seeds that a seeded
/// fuzz then corrupts. Passing means the process is still alive at the end (a trap ends it without the PASS line).
@MainActor
enum ParserFuzzChecks {
    static func run(iterations: Int = 3000) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "IkagoParserFuzz-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // Files go through ImportFileParser.read, which picks the parser by name and first bytes, as Import does.
        let bookmarks = Data("""
            <!DOCTYPE NETSCAPE-Bookmark-file-1><DL><p><DT><H3>Bar</H3><DL><p><DT><A HREF="https://a.test/" ADD_DATE="1">A &amp; B</A>
            <DT><A HREF="https://b.test/">B</A></DL><p></DL>
            """.utf8)
        let history = Data((#"{"history":[{"url":"https://a.test/","title":"A","time_usec":1700000000000000,"visit_count":3}],"#
                            + #""tabs":[{"url":"https://b.test/","title":"B"}],"#
                            + #""cookies":[{"domain":"a.test","name":"n","value":"v","path":"/","expirationDate":1e10}]}"#).utf8)
        let passwords = Data("name,url,username,password,note\nsite,https://site.test/login,bo,secret,\n".utf8)
        let cookies = Data("a.test\tTRUE\t/\tFALSE\t2000000000\tname\tvalue\n".utf8)
        let zip = ZipArchive.write([.init(name: "Bookmarks.html", data: bookmarks), .init(name: "History.json", data: history),
                                    .init(name: "Passwords.csv", data: passwords)])
        let files: [(String, Data)] = [
            ("Session.snss", BrowserImportChecks.sessionFixture()), ("Grouped.snss", ChromiumGroupFixture.grouped()),
            ("Export.zip", zip), ("Bookmarks.html", bookmarks), ("History.json", history), ("Passwords.csv", passwords),
            ("Cookies.txt", cookies), ("Session.jsonlz4", firefox(history)),
        ]
        let cookieFile = safariCookies()
        let crx = crxPackage()
        let csvText = String(decoding: passwords, as: UTF8.self)

        // Exact values random corruption rarely makes: numbers past every integer type, in a file JSON allows.
        let huge = Data(#"{"history":[{"url":"https://a.test/","title":"A","time":1e300,"time_usec":-1e300,"visit_count":1e300,"typed_count":1e19}],"cookies":[{"domain":"a.test","name":"n","value":"v","expirationDate":1e300}]}"#.utf8)
        let hugeURL = folder.appending(path: "Huge.json")
        try? huge.write(to: hugeURL)
        _ = try? ImportFileParser.read(hugeURL)
        print("IKTEST parserfuzz PASS numbers past every integer type don't end Ikago")

        var alive = 0
        var rng = MediaParserChecks.SeededRandom(seed: 0x1CA61)
        for index in 0..<iterations {
            let (name, seed) = files[index % files.count]
            let url = folder.appending(path: "\(index % 4)-\(name)")
            try? mutate(seed, &rng).write(to: url)
            _ = try? ImportFileParser.read(url, chromiumGroupNamespace: "fuzz")
            _ = try? ImportFileParser.safariCookies(mutate(cookieFile, &rng))
            _ = try? CRXVerifier.verifiedArchive(mutate(crx.data, &rng), id: crx.id, requirePublisher: false)
            _ = try? ZipArchive.read(mutate(zip, &rng))
            _ = try? PasswordImport.parse(String(decoding: mutate(Data(csvText.utf8), &rng), as: UTF8.self))
            alive += 1
        }
        print("IKTEST parserfuzz PASS \(alive) rounds of corrupted session, archive, bookmark, history, cookie, password and extension files")
        // The seeds themselves must still parse, or the fuzz would only be testing the first check.
        let seedsParse = files.allSatisfy { name, data in
            let url = folder.appending(path: "seed-\(name)")
            try? data.write(to: url)
            return (try? ImportFileParser.read(url, chromiumGroupNamespace: "fuzz")) != nil
        } && ((try? ImportFileParser.safariCookies(cookieFile))?.isEmpty == false)
          && (try? CRXVerifier.verifiedArchive(crx.data, id: crx.id, requirePublisher: false)) != nil
        print("IKTEST parserfuzz \(seedsParse ? "PASS" : "FAIL") every valid seed parses")
        print("IKTEST parserfuzzchecks \(seedsParse ? "PASS" : "FAIL")")
    }

    /// Flipped bytes, truncation, and huge values: the same corruptions as `MediaParserChecks`.
    static func mutate(_ data: Data, _ rng: inout MediaParserChecks.SeededRandom) -> Data {
        var bytes = [UInt8](data)
        guard bytes.count > 8 else { return data }
        switch rng.next() % 4 {
        case 0: for _ in 0..<(1 + rng.next() % 8) { bytes[Int(rng.next() % UInt64(bytes.count))] = UInt8(truncatingIfNeeded: rng.next()) }
        case 1: bytes = Array(bytes.prefix(Int(rng.next() % UInt64(bytes.count))))
        case 2:
            let at = Int(rng.next() % UInt64(bytes.count - 4))
            for offset in 0..<4 { bytes[at + offset] = offset == 3 ? UInt8(truncatingIfNeeded: rng.next()) : 0xFF }
        default:
            let at = Int(rng.next() % UInt64(bytes.count - 8))
            bytes.replaceSubrange(at..<at + 8, with: MediaParserChecks.Fixture.be64(rng.next()))
        }
        return Data(bytes)
    }

    /// Firefox's mozLz40: magic, little-endian size, raw LZ4.
    static func firefox(_ json: Data) -> Data {
        var out = [UInt8](repeating: 0, count: json.count + 64)
        let written = json.withUnsafeBytes { source in
            compression_encode_buffer(&out, out.count, source.bindMemory(to: UInt8.self).baseAddress!, json.count, nil, COMPRESSION_LZ4_RAW)
        }
        let size = UInt32(json.count)
        return Data("mozLz40\0".utf8) + Data([UInt8(size & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 24)])
            + Data(out.prefix(written))
    }

    /// Safari's Cookies.binarycookies with one page and one cookie, laid out as `ImportFileParser.safariCookies` reads it.
    static func safariCookies() -> Data {
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)] }
        func be32(_ v: Int) -> [UInt8] { le32(v).reversed() }
        let strings = Array("a.test\0name\0/\0value\0".utf8)
        var cookie = le32(56 + strings.count) + le32(0) + le32(5) + le32(0)
        cookie += le32(56) + le32(56 + 7) + le32(56 + 12) + le32(56 + 14) + le32(0) + le32(0)
        withUnsafeBytes(of: (2_000_000_000.0 as Double).bitPattern.littleEndian) { cookie += $0 }
        withUnsafeBytes(of: (1_000_000_000.0 as Double).bitPattern.littleEndian) { cookie += $0 }
        cookie += strings
        let page = [0x00, 0x00, 0x01, 0x00] + le32(1) + le32(16) + le32(0) + cookie
        return Data(Array("cook".utf8) + be32(1) + be32(page.count) + page)
    }

    /// A store package signed by a fresh developer key, as `CRXVerifierChecks` builds them.
    static func crxPackage() -> (data: Data, id: String) {
        let developer = P256.Signing.PrivateKey()
        let key = [UInt8](developer.publicKey.derRepresentation)
        let crxID = Array(SHA256.hash(data: key).prefix(16))
        func varint(_ value: Int) -> [UInt8] {
            var value = value, out: [UInt8] = []
            repeat { var byte = UInt8(value & 0x7F); value >>= 7; if value > 0 { byte |= 0x80 }; out.append(byte) } while value > 0
            return out
        }
        func field(_ number: Int, _ value: [UInt8]) -> [UInt8] { varint(number << 3 | 2) + varint(value.count) + value }
        let archive = ZipArchive.write([.init(name: "manifest.json", data: Data(#"{"manifest_version":3,"name":"x","version":"1"}"#.utf8))])
        let signedHeader = field(1, crxID)
        var message = Data("CRX3 SignedData".utf8) + [0]
        withUnsafeBytes(of: UInt32(signedHeader.count).littleEndian) { message.append(contentsOf: $0) }
        message.append(contentsOf: signedHeader); message.append(archive)
        let signature = [UInt8]((try? developer.signature(for: message).derRepresentation) ?? Data())
        let header = field(3, field(1, key) + field(2, signature)) + field(10000, signedHeader)
        var data = Data("Cr24".utf8)
        withUnsafeBytes(of: UInt32(3).littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(header.count).littleEndian) { data.append(contentsOf: $0) }
        return (data + header + archive, CRXVerifier.extensionID(crxID))
    }
}
#endif
