#if os(macOS)
import Foundation
import SQLite3
import WhodisCore

struct ChatHandle {
    let id: String
    let kind: HandleKind
    let messageCount: Int
    let lastMessage: Date?
}

/// Reads ~/Library/Messages/chat.db. Opened with SQLITE_OPEN_READONLY: whodis never writes here.
enum MessagesDB {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db").path
    }

    /// Every phone/email handle you've exchanged messages with, most recent first.
    static func activeHandles(at path: String = defaultPath) throws -> [ChatHandle] {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw Failure(description: errorMessage(db))
        }

        let sql = """
            SELECT h.id, COUNT(m.ROWID), MAX(m.date)
            FROM handle h
            JOIN message m ON m.handle_id = h.ROWID
            GROUP BY h.id
            ORDER BY MAX(m.date) DESC
            """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Failure(description: errorMessage(db))
        }

        var handles: [ChatHandle] = []
        var seen = Set<String>()
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw Failure(description: errorMessage(db)) }
            guard let text = sqlite3_column_text(stmt, 0) else { continue }

            let id = String(cString: text)
            guard let kind = HandleKind.classify(id) else { continue }

            // The same person can appear under both iMessage and SMS, or with different email casing.
            let dedupeKey = kind == .email ? id.lowercased() : PhoneKey.significantDigits(id)
            guard seen.insert(dedupeKey).inserted else { continue }

            handles.append(ChatHandle(
                id: id,
                kind: kind,
                messageCount: Int(sqlite3_column_int64(stmt, 1)),
                lastMessage: appleMessageDate(sqlite3_column_int64(stmt, 2))
            ))
        }
        return handles
    }

    private static func errorMessage(_ db: OpaquePointer?) -> String {
        guard let db, let message = sqlite3_errmsg(db) else { return "unknown SQLite error" }
        return String(cString: message)
    }
}
#endif
