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
                    { "name": "5h", "label": "5h limit", "usedPercent": 42.4, "remainingPercent": 57.6, "resetsAt": "2026-06-22T05:00:00.000Z" },
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
        XCTAssertEqual(snapshot.fiveHour.remainingPercent, 58)
        XCTAssertEqual(snapshot.weekly.name, "Weekly")
        XCTAssertEqual(snapshot.weekly.usedPercent, 7)
        XCTAssertEqual(snapshot.weekly.remainingPercent, 93)
        XCTAssertEqual(snapshot.skillsCount, 2)
        XCTAssertEqual(snapshot.eventsCount, 2)
        XCTAssertEqual(snapshot.recentEvents.map(\.id), ["e2", "e1"])
        XCTAssertEqual(snapshot.recentEvents.first?.eventType, "Stop")
        XCTAssertEqual(snapshot.recentEvents.last?.toolName, "Bash")
        XCTAssertEqual(snapshot.projectPath, "/Users/lane/Desktop/codex/Abar")
        XCTAssertEqual(snapshot.tasks, [])
        XCTAssertEqual(snapshot.activityState, .idle)
    }

    func testDerivesRunningTaskFromPromptEvent() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertEvent(
                db,
                id: "prompt-1",
                eventType: "UserPromptSubmit",
                projectPath: "/Users/lane/Desktop/codex/Abar",
                sessionId: "session-1",
                payloadJSON: """
                {"prompt":"修复菜单栏显示问题并验证","cwd":"/Users/lane/Desktop/codex/Abar","session_id":"session-1","turn_id":"turn-1","transcript_path":"/tmp/session-1.jsonl"}
                """,
                createdAt: "2026-06-22T01:00:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T01:01:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.activityState, .working)
        XCTAssertEqual(snapshot.tasks.count, 1)
        XCTAssertEqual(snapshot.tasks.first?.id, "session-1:turn-1")
        XCTAssertEqual(snapshot.tasks.first?.projectName, "Abar")
        XCTAssertEqual(snapshot.tasks.first?.promptPreview, "修复菜单栏...")
        XCTAssertEqual(snapshot.tasks.first?.sessionId, "session-1")
        XCTAssertEqual(snapshot.tasks.first?.turnId, "turn-1")
        XCTAssertEqual(snapshot.tasks.first?.transcriptPath, "/tmp/session-1.jsonl")
        XCTAssertEqual(snapshot.tasks.first?.state, .running)
        XCTAssertEqual(snapshot.tasks.first?.startedAt, Self.date("2026-06-22T01:00:00.000Z"))
        XCTAssertEqual(snapshot.tasks.first?.lastActivityAt, Self.date("2026-06-22T01:00:00.000Z"))
        XCTAssertEqual(snapshot.tasks.first?.durationSeconds, 0)
        XCTAssertNil(snapshot.tasks.first?.completedAt)
    }

    func testRunningTaskDurationUsesLatestTurnActivityInsteadOfCurrentTime() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertEvent(
                db,
                id: "prompt-1",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-1",
                payloadJSON: """
                {"prompt":"检查现在的问题","cwd":"/tmp/ProjectA","session_id":"session-1","turn_id":"turn-1","transcript_path":"/tmp/session-1.jsonl"}
                """,
                createdAt: "2026-06-22T01:00:00.000Z"
            )
            insertEvent(
                db,
                id: "tool-1",
                eventType: "PostToolUse",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-1",
                payloadJSON: """
                {"cwd":"/tmp/ProjectA","session_id":"session-1","turn_id":"turn-1","tool_name":"Bash"}
                """,
                createdAt: "2026-06-22T01:05:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T01:06:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks.count, 1)
        XCTAssertEqual(snapshot.tasks.first?.lastActivityAt, Self.date("2026-06-22T01:05:00.000Z"))
        XCTAssertEqual(snapshot.tasks.first?.durationSeconds, 300)
    }

    func testHidesUnclosedPromptAfterFifteenMinutesWithoutActivity() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertEvent(
                db,
                id: "prompt-1",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-1",
                payloadJSON: """
                {"prompt":"旧任务","cwd":"/tmp/ProjectA","session_id":"session-1","turn_id":"turn-1","transcript_path":"/tmp/session-1.jsonl"}
                """,
                createdAt: "2026-06-22T01:00:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T01:16:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks, [])
        XCTAssertEqual(snapshot.activityState, .idle)
    }

    func testDerivesCompletedTaskWhenStopMatchesPromptTurn() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertPromptAndStop(
                db,
                projectPath: "/tmp/ProjectA",
                sessionId: "session-1",
                turnId: "turn-1",
                prompt: "检查 quota 状态",
                promptAt: "2026-06-22T01:00:00.000Z",
                stopAt: "2026-06-22T01:02:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T01:02:30.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.activityState, .idle)
        XCTAssertEqual(snapshot.tasks.count, 1)
        XCTAssertEqual(snapshot.tasks.first?.id, "session-1:turn-1")
        XCTAssertEqual(snapshot.tasks.first?.state, .completed)
        XCTAssertEqual(snapshot.tasks.first?.completedAt, Self.date("2026-06-22T01:02:00.000Z"))
        XCTAssertEqual(snapshot.tasks.first?.lastActivityAt, Self.date("2026-06-22T01:02:00.000Z"))
        XCTAssertEqual(snapshot.tasks.first?.durationSeconds, 120)
    }

    func testHidesCompletedTaskAfterThreeMinutes() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertPromptAndStop(
                db,
                projectPath: "/tmp/ProjectA",
                sessionId: "session-1",
                turnId: "turn-1",
                prompt: "检查 quota 状态",
                promptAt: "2026-06-22T01:00:00.000Z",
                stopAt: "2026-06-22T01:02:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T01:05:01.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks, [])
        XCTAssertEqual(snapshot.activityState, .idle)
    }

    func testNewPromptForSameProjectHidesOlderCompletedTask() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertPromptAndStop(
                db,
                projectPath: "/tmp/ProjectA",
                sessionId: "session-1",
                turnId: "turn-1",
                prompt: "检查 quota 状态",
                promptAt: "2026-06-22T01:00:00.000Z",
                stopAt: "2026-06-22T01:02:00.000Z"
            )
            insertEvent(
                db,
                id: "prompt-2",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-2",
                payloadJSON: """
                {"prompt":"继续修复跳转","cwd":"/tmp/ProjectA","session_id":"session-2","turn_id":"turn-2","transcript_path":"/tmp/session-2.jsonl"}
                """,
                createdAt: "2026-06-22T01:02:30.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T01:03:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks.map(\.id), ["session-2:turn-2"])
        XCTAssertEqual(snapshot.tasks.first?.state, .running)
        XCTAssertEqual(snapshot.activityState, .working)
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

    private func createReaderSchema(_ db: OpaquePointer) {
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
    }

    private func insertPromptAndStop(
        _ db: OpaquePointer,
        projectPath: String,
        sessionId: String,
        turnId: String,
        prompt: String,
        promptAt: String,
        stopAt: String
    ) {
        insertEvent(
            db,
            id: "prompt-\(turnId)",
            eventType: "UserPromptSubmit",
            projectPath: projectPath,
            sessionId: sessionId,
            payloadJSON: """
            {"prompt":"\(prompt)","cwd":"\(projectPath)","session_id":"\(sessionId)","turn_id":"\(turnId)","transcript_path":"/tmp/\(sessionId).jsonl"}
            """,
            createdAt: promptAt
        )
        insertEvent(
            db,
            id: "stop-\(turnId)",
            eventType: "Stop",
            projectPath: projectPath,
            sessionId: sessionId,
            payloadJSON: """
            {"cwd":"\(projectPath)","session_id":"\(sessionId)","turn_id":"\(turnId)","transcript_path":"/tmp/\(sessionId).jsonl"}
            """,
            createdAt: stopAt
        )
    }

    private func insertEvent(
        _ db: OpaquePointer,
        id: String,
        eventType: String,
        projectPath: String,
        sessionId: String,
        payloadJSON: String,
        createdAt: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var statement: OpaquePointer?
        let sql = """
            INSERT INTO events (
              id, agent, event_type, project_path, session_id, tool_name,
              tool_use_id, status, payload_json, created_at
            ) VALUES (?, 'codex', ?, ?, ?, NULL, NULL, 'unknown', ?, ?)
            """
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK, file: file, line: line)
        guard let statement else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 2, eventType, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 3, projectPath, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 4, sessionId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 5, payloadJSON, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 6, createdAt, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE, file: file, line: line)
    }

    private static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)!
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
