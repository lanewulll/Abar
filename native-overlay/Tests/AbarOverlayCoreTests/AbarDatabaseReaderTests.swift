import AbarOverlayCore
import SQLite3
import XCTest

final class AbarDatabaseReaderTests: XCTestCase {
    func testLoadsSnapshotFromExistingAbarDatabaseShape() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            exec(db, """
                CREATE TABLE app_config (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL);
                CREATE TABLE skills (
                  id TEXT PRIMARY KEY,
                  project_id TEXT,
                  name TEXT NOT NULL,
                  description TEXT NOT NULL,
                  path TEXT NOT NULL,
                  source TEXT NOT NULL,
                  skill_md_path TEXT NOT NULL,
                  has_skill_md INTEGER NOT NULL,
                  last_modified_at TEXT,
                  scanned_at TEXT NOT NULL
                );
                CREATE TABLE events (
                  id TEXT PRIMARY KEY,
                  agent TEXT NOT NULL,
                  event_type TEXT NOT NULL,
                  project_path TEXT,
                  session_id TEXT,
                  tool_name TEXT,
                  tool_use_id TEXT,
                  status TEXT,
                  payload_json TEXT,
                  created_at TEXT NOT NULL
                );
                CREATE TABLE quota_snapshots (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  provider TEXT NOT NULL,
                  source TEXT NOT NULL,
                  confidence TEXT NOT NULL,
                  snapshot_json TEXT NOT NULL,
                  error TEXT,
                  created_at TEXT NOT NULL
                );
                """)
            exec(db, """
                INSERT INTO app_config VALUES ('project_path', '/Users/lane/Desktop/codex/Abar', '2026-06-22T00:00:00.000Z');
                INSERT INTO skills VALUES ('s1', NULL, 'swift', 'Swift skill', '/tmp/s', 'user', '/tmp/s/SKILL.md', 1, NULL, '2026-06-22T00:00:00.000Z');
                INSERT INTO skills VALUES ('s2', NULL, 'macos', 'macOS skill', '/tmp/m', 'user', '/tmp/m/SKILL.md', 1, NULL, '2026-06-22T00:00:00.000Z');
                INSERT INTO events VALUES ('e1', 'codex', 'PostToolUse', '/tmp', 'session', 'Bash', 'tool', 'success', '{}', '2026-06-22T01:00:00.000Z');
                INSERT INTO events VALUES ('e2', 'codex', 'Stop', '/tmp', 'session', NULL, NULL, 'unknown', '{}', '2026-06-22T01:01:00.000Z');
                """)

            let json = """
                {
                  "provider": "codex",
                  "source": "local_estimate",
                  "confidence": "medium",
                  "updatedAt": "2026-06-22T01:02:00.000Z",
                  "windows": [
                    { "name": "5h", "label": "5h limit", "usedPercent": 42.4, "resetsAt": "2026-06-22T05:00:00.000Z" },
                    { "name": "weekly", "label": "Weekly", "usedPercent": 7 }
                  ]
                }
                """
            insertQuota(db, json: json)
        }

        let reader = AbarDatabaseReader(databasePath: dbURL.path, now: { Date(timeIntervalSince1970: 100) })
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.fiveHour.name, "5h limit")
        XCTAssertEqual(snapshot.fiveHour.usedPercent, 42)
        XCTAssertEqual(snapshot.weekly.name, "Weekly")
        XCTAssertEqual(snapshot.weekly.usedPercent, 7)
        XCTAssertEqual(snapshot.skillsCount, 2)
        XCTAssertEqual(snapshot.eventsCount, 2)
        XCTAssertEqual(snapshot.recentEvents.map(\.id), ["e2", "e1"])
        XCTAssertEqual(snapshot.recentEvents.first?.eventType, "Stop")
        XCTAssertEqual(snapshot.recentEvents.last?.toolName, "Bash")
        XCTAssertEqual(snapshot.projectPath, "/Users/lane/Desktop/codex/Abar")
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-native-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func withSQLiteDatabase(at path: String, body: (OpaquePointer) throws -> Void) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        guard let db else {
            XCTFail("database did not open")
            return
        }
        defer { sqlite3_close(db) }
        try body(db)
    }

    private func exec(_ db: OpaquePointer, _ sql: String, file: StaticString = #filePath, line: UInt = #line) {
        var error: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(db, sql, nil, nil, &error)
        if status != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown sqlite error"
            sqlite3_free(error)
            XCTFail(message, file: file, line: line)
        }
    }

    private func insertQuota(_ db: OpaquePointer, json: String, file: StaticString = #filePath, line: UInt = #line) {
        var statement: OpaquePointer?
        let sql = """
            INSERT INTO quota_snapshots (provider, source, confidence, snapshot_json, error, created_at)
            VALUES ('codex', 'local_estimate', 'medium', ?, NULL, '2026-06-22T01:02:00.000Z')
            """
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK, file: file, line: line)
        guard let statement else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, json, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE, file: file, line: line)
    }
}
