import Foundation
import SQLite3

public enum AbarDatabaseReaderError: Error, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
}

public final class AbarDatabaseReader {
    private let databasePath: String
    private let now: () -> Date

    public init(databasePath: String, now: @escaping () -> Date = Date.init) {
        self.databasePath = databasePath
        self.now = now
    }

    public func loadSnapshot() throws -> AbarSnapshot {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databasePath, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let db { sqlite3_close(db) }
            throw AbarDatabaseReaderError.openFailed(message)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2_000)

        let quota = try latestQuota(db: db)
        let events = try recentEvents(db: db, limit: 6)
        return AbarSnapshot(
            fiveHour: quota.fiveHour,
            weekly: quota.weekly,
            skillsCount: try count(db: db, table: "skills"),
            eventsCount: try count(db: db, table: "events"),
            recentEvents: events,
            projectPath: try configValue(db: db, key: "project_path"),
            loadedAt: now()
        )
    }

    private func latestQuota(db: OpaquePointer) throws -> (fiveHour: QuotaWindowSummary, weekly: QuotaWindowSummary) {
        guard let json = try firstText(
            db: db,
            sql: "SELECT snapshot_json FROM quota_snapshots ORDER BY created_at DESC LIMIT 1",
            bindings: []
        ) else {
            return (.unavailable(name: "5h"), .unavailable(name: "Weekly"))
        }

        guard
            let data = json.data(using: .utf8),
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let windows = root["windows"] as? [[String: Any]]
        else {
            return (.unavailable(name: "5h"), .unavailable(name: "Weekly"))
        }

        return (
            quotaWindow(named: "5h", in: windows, fallbackLabel: "5h"),
            quotaWindow(named: "weekly", in: windows, fallbackLabel: "Weekly")
        )
    }

    private func quotaWindow(
        named name: String,
        in windows: [[String: Any]],
        fallbackLabel: String
    ) -> QuotaWindowSummary {
        guard let window = windows.first(where: { ($0["name"] as? String) == name }) else {
            return .unavailable(name: fallbackLabel)
        }

        let label = (window["label"] as? String) ?? fallbackLabel
        let percent = normalizedPercent(window["usedPercent"])
        let resetsAt = (window["resetsAt"] as? String).flatMap(Self.parseISODate)
        return QuotaWindowSummary(name: label, usedPercent: percent, resetsAt: resetsAt)
    }

    private func normalizedPercent(_ value: Any?) -> Int? {
        let doubleValue: Double?
        if let number = value as? NSNumber {
            doubleValue = number.doubleValue
        } else if let number = value as? Double {
            doubleValue = number
        } else if let string = value as? String {
            doubleValue = Double(string)
        } else {
            doubleValue = nil
        }

        guard let doubleValue else { return nil }
        return Int(max(0, min(100, doubleValue)).rounded())
    }

    private func recentEvents(db: OpaquePointer, limit: Int) throws -> [AbarEventSummary] {
        var statement: OpaquePointer?
        let sql = """
            SELECT id, event_type, tool_name, status, created_at
            FROM events
            ORDER BY created_at DESC
            LIMIT ?
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AbarDatabaseReaderError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var events: [AbarEventSummary] = []
        var stepStatus = sqlite3_step(statement)
        while stepStatus == SQLITE_ROW {
            events.append(
                AbarEventSummary(
                    id: columnText(statement, 0) ?? UUID().uuidString,
                    eventType: columnText(statement, 1) ?? "Unknown",
                    toolName: columnText(statement, 2),
                    status: columnText(statement, 3) ?? "unknown",
                    createdAt: columnText(statement, 4).flatMap(Self.parseISODate)
                )
            )
            stepStatus = sqlite3_step(statement)
        }

        guard stepStatus == SQLITE_DONE else {
            throw AbarDatabaseReaderError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
        return events
    }

    private func count(db: OpaquePointer, table: String) throws -> Int {
        let allowedTables = ["skills", "events"]
        precondition(allowedTables.contains(table))
        let sql = "SELECT COUNT(*) FROM \(table)"
        return Int(try firstInt(db: db, sql: sql, bindings: []) ?? 0)
    }

    private func configValue(db: OpaquePointer, key: String) throws -> String? {
        try firstText(db: db, sql: "SELECT value FROM app_config WHERE key = ? LIMIT 1", bindings: [key])
    }

    private func firstText(db: OpaquePointer, sql: String, bindings: [String]) throws -> String? {
        try querySingle(db: db, sql: sql, bindings: bindings) { statement in
            columnText(statement, 0)
        }
    }

    private func firstInt(db: OpaquePointer, sql: String, bindings: [String]) throws -> Int64? {
        try querySingle(db: db, sql: sql, bindings: bindings) { statement in
            sqlite3_column_type(statement, 0) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 0)
        }
    }

    private func querySingle<T>(
        db: OpaquePointer,
        sql: String,
        bindings: [String],
        map: (OpaquePointer) -> T?
    ) throws -> T? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AbarDatabaseReaderError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }

        let stepStatus = sqlite3_step(statement)
        if stepStatus == SQLITE_ROW {
            return map(statement)
        }
        guard stepStatus == SQLITE_DONE else {
            throw AbarDatabaseReaderError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
        return nil
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: pointer)
    }

    private static func parseISODate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
