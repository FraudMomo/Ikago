import Foundation
import SQLite3

/// Read-only SQLite access includes committed WAL records without copying or editing the source.
final class ImportDatabase {
    private var database: OpaquePointer?
    init(_ file: URL) throws {
        // Retain Foundation's specific missing/access error; SQLite CANTOPEN alone is ambiguous.
        let probe = try FileHandle(forReadingFrom: file)
        try probe.close()
        guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            let failure = databaseError(fallback: "The browser database couldn’t be opened. Close the source browser and try again.")
            if let database { sqlite3_close(database) }
            database = nil
            throw failure
        }
        sqlite3_busy_timeout(database, 1000)
        sqlite3_exec(database, "PRAGMA query_only=ON", nil, nil, nil)
    }
    deinit { if let database { sqlite3_close(database) } }

    private func databaseError(fallback: String) -> Error {
        if let database {
            let system = sqlite3_system_errno(database)
            if system == EACCES || system == EPERM { return NSError(domain: NSPOSIXErrorDomain, code: Int(system)) }
            let code = sqlite3_errcode(database)
            if code == SQLITE_PERM || code == SQLITE_AUTH { return CocoaError(.fileReadNoPermission) }
            if code == SQLITE_BUSY || code == SQLITE_LOCKED {
                return NSError(domain: "Ikago.ImportDatabase", code: Int(code), userInfo: [NSLocalizedDescriptionKey:
                    "The browser database is busy. Close the source browser and try again."])
            }
        }
        return NSError(domain: "Ikago.ImportDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: fallback])
    }

    func rows(_ sql: String) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw databaseError(fallback: "This browser database has an unsupported schema.")
        }
        defer { sqlite3_finalize(statement) }
        var rows: [[String: Any]] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW, rows.count < 50_000 {
            var row: [String: Any] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let key = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: row[key] = sqlite3_column_int64(statement, index)
                case SQLITE_FLOAT: row[key] = sqlite3_column_double(statement, index)
                case SQLITE_TEXT: if let value = sqlite3_column_text(statement, index) { row[key] = String(cString: value) }
                case SQLITE_BLOB:
                    if let value = sqlite3_column_blob(statement, index) { row[key] = Data(bytes: value, count: Int(sqlite3_column_bytes(statement, index))) }
                default: break
                }
            }
            rows.append(row)
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE || rows.count == 50_000 else { throw databaseError(fallback: "The browser database couldn’t be read. Close the source browser and try again.") }
        return rows
    }
}
