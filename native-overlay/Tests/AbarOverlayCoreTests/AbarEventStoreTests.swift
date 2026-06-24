import AbarOverlayCore
import SQLite3
import XCTest

final class AbarEventStoreTests: XCTestCase {
    func testNormalizesHookPayloadToMinimalTaskMetadata() throws {
        let payload = Data(
            """
            {
              "id": "event-1",
              "hook_event_name": "PostToolUse",
              "tool_name": "Bash",
              "status": "success",
              "cwd": "/tmp/project",
              "session_id": "session-1",
              "turn_id": "turn-1",
              "prompt": "这是不应该完整写入数据库的很长提示词内容，只保留一个短预览即可。",
              "transcript_path": "/private/transcript.jsonl",
              "authorization": "Bearer secret"
            }
            """.utf8
        )

        let event = try AbarHookEventNormalizer.normalize(
            data: payload,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(event.id, "event-1")
        XCTAssertEqual(event.eventType, "PostToolUse")
        XCTAssertEqual(event.toolName, "Bash")
        XCTAssertEqual(event.status, "success")
        XCTAssertEqual(event.projectPath, "/tmp/project")
        XCTAssertTrue(event.payloadJSON.contains(#""prompt_preview""#))
        XCTAssertFalse(event.payloadJSON.contains("这是不应该完整写入数据库的很长提示词内容"))
        XCTAssertFalse(event.payloadJSON.contains("transcript_path"))
        XCTAssertFalse(event.payloadJSON.contains("authorization"))
    }

    func testInitializeMigratesLegacyPayloadAndQuotaRawData() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-privacy-migration-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        try createLegacyDatabase(at: dbURL.path)

        let store = AbarEventStore(
            databasePath: dbURL.path,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        try store.initialize(defaultPort: 3987)

        let payload = try textValue(
            dbURL.path,
            sql: "SELECT payload_json FROM events WHERE id = 'legacy-event'"
        )
        let quota = try textValue(
            dbURL.path,
            sql: "SELECT snapshot_json FROM quota_snapshots ORDER BY id DESC LIMIT 1"
        )
        XCTAssertFalse(payload.contains("完整的旧提示词内容不应该在迁移后继续存在"))
        XCTAssertFalse(payload.contains("transcript_path"))
        XCTAssertTrue(payload.contains("prompt_preview"))
        XCTAssertFalse(quota.contains(#""raw""#))
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(dbURL.path).privacy-backup"))
    }

    func testInitializePrunesEventsAndQuotaOlderThanRolling24Hours() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-retention-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let store = AbarEventStore(databasePath: dbURL.path, now: { now })
        try store.initialize(defaultPort: 3987)
        try store.insertEvent(
            AbarStoredEvent(
                id: "old-event",
                eventType: "Stop",
                projectPath: "/tmp/project",
                sessionId: "session",
                toolName: nil,
                toolUseId: nil,
                status: "unknown",
                payloadJSON: "{}",
                createdAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(-86_401))
            )
        )
        try store.insertEvent(
            AbarStoredEvent(
                id: "recent-event",
                eventType: "Stop",
                projectPath: "/tmp/project",
                sessionId: "session",
                toolName: nil,
                toolUseId: nil,
                status: "unknown",
                payloadJSON: "{}",
                createdAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
            )
        )

        try store.pruneExpiredData()

        XCTAssertEqual(try intValue(dbURL.path, sql: "SELECT COUNT(*) FROM events"), 1)
    }

    func testDuplicateQuotaSnapshotIsNotWrittenAgainWithinHeartbeatWindow() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-quota-dedupe-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let store = AbarEventStore(databasePath: dbURL.path)
        try store.initialize(defaultPort: 3987)
        let snapshot = AbarStoredQuotaSnapshot(
            source: "internal_web_api",
            confidence: "high",
            snapshotJSON: #"{"provider":"codex","windows":[]}"#,
            error: nil
        )

        try store.insertQuotaSnapshot(snapshot)
        try store.insertQuotaSnapshot(snapshot)

        XCTAssertEqual(try intValue(dbURL.path, sql: "SELECT COUNT(*) FROM quota_snapshots"), 1)
    }

    func testEventStoreCreatesSchemaAndPersistsEventsForReader() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-native-store-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let store = AbarEventStore(databasePath: dbURL.path)
        try store.initialize(defaultPort: 3987)
        try store.insertEvent(
            AbarStoredEvent(
                id: "native-event",
                eventType: "PreToolUse",
                projectPath: "/tmp/project",
                sessionId: "session",
                toolName: "Bash",
                toolUseId: "tool",
                status: "unknown",
                payloadJSON: #"{"ok":true}"#,
                createdAt: "2026-06-22T01:00:00.000Z"
            )
        )

        let snapshot = try AbarDatabaseReader(databasePath: dbURL.path).loadSnapshot()

        XCTAssertEqual(snapshot.eventsCount, 1)
        XCTAssertEqual(snapshot.recentEvents.first?.id, "native-event")
        XCTAssertEqual(snapshot.recentEvents.first?.eventType, "PreToolUse")
    }

    func testInsertEventPersistsLatestNonEmptyProjectPath() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-native-store-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let store = AbarEventStore(databasePath: dbURL.path)
        try store.initialize(defaultPort: 3987)

        try store.insertEvent(
            AbarStoredEvent(
                id: "event-with-project",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/project-a",
                sessionId: "session",
                toolName: nil,
                toolUseId: nil,
                status: "unknown",
                payloadJSON: "{}",
                createdAt: "2026-06-22T01:00:00.000Z"
            )
        )
        try store.insertEvent(
            AbarStoredEvent(
                id: "event-without-project",
                eventType: "Stop",
                projectPath: nil,
                sessionId: "session",
                toolName: nil,
                toolUseId: nil,
                status: "unknown",
                payloadJSON: "{}",
                createdAt: "2026-06-22T01:01:00.000Z"
            )
        )

        XCTAssertEqual(try store.configValue(key: "project_path"), "/tmp/project-a")
    }

    func testEventStorePersistsSkillsAndQuotaForReader() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-native-store-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let store = AbarEventStore(databasePath: dbURL.path)
        try store.initialize(defaultPort: 3987)
        try store.replaceSkills([
            AbarStoredSkill(
                id: "skill-1",
                name: "Swift",
                description: "Native Swift skill",
                path: "/tmp/swift",
                source: "user",
                skillMDPath: "/tmp/swift/SKILL.md",
                lastModifiedAt: nil
            )
        ], scannedAt: "2026-06-22T01:00:00.000Z")
        try store.insertQuotaSnapshot(
            AbarStoredQuotaSnapshot(
                source: "internal_web_api",
                confidence: "high",
                snapshotJSON: """
                {"provider":"codex","source":"internal_web_api","confidence":"high","windows":[{"name":"5h","usedPercent":11,"remainingPercent":89},{"name":"weekly","usedPercent":22}],"updatedAt":"2026-06-22T01:00:00.000Z"}
                """,
                error: nil
            )
        )

        let snapshot = try AbarDatabaseReader(databasePath: dbURL.path).loadSnapshot()

        XCTAssertEqual(snapshot.skillsCount, 1)
        XCTAssertEqual(snapshot.fiveHour.usedPercent, 11)
        XCTAssertEqual(snapshot.fiveHour.remainingPercent, 89)
        XCTAssertEqual(snapshot.weekly.usedPercent, 22)
        XCTAssertEqual(snapshot.weekly.remainingPercent, 78)
    }

    private func createLegacyDatabase(at path: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        guard let db else { return }
        defer { sqlite3_close(db) }
        let createdAt = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_799_999_900))
        let schema = """
        CREATE TABLE app_config (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL);
        CREATE TABLE projects (id TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE, is_active INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
        CREATE TABLE skills (id TEXT PRIMARY KEY, project_id TEXT, name TEXT NOT NULL, description TEXT NOT NULL, path TEXT NOT NULL, source TEXT NOT NULL, skill_md_path TEXT NOT NULL, has_skill_md INTEGER NOT NULL, last_modified_at TEXT, scanned_at TEXT NOT NULL);
        CREATE TABLE events (id TEXT PRIMARY KEY, agent TEXT NOT NULL, event_type TEXT NOT NULL, project_path TEXT, session_id TEXT, tool_name TEXT, tool_use_id TEXT, status TEXT, payload_json TEXT, created_at TEXT NOT NULL);
        CREATE TABLE quota_snapshots (id INTEGER PRIMARY KEY AUTOINCREMENT, provider TEXT NOT NULL, source TEXT NOT NULL, confidence TEXT NOT NULL, snapshot_json TEXT NOT NULL, error TEXT, created_at TEXT NOT NULL);
        INSERT INTO events VALUES ('legacy-event','codex','UserPromptSubmit','/tmp/project','session',NULL,NULL,'unknown','{"prompt":"完整的旧提示词内容不应该在迁移后继续存在","transcript_path":"/private/file","turn_id":"turn"}','\(createdAt)');
        INSERT INTO quota_snapshots (provider,source,confidence,snapshot_json,error,created_at) VALUES ('codex','internal_web_api','high','{"windows":[],"raw":{"account":"private"}}',NULL,'\(createdAt)');
        """
        XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, nil), SQLITE_OK)
    }

    private func textValue(_ path: String, sql: String) throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else { return "" }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return "" }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return "" }
        return String(cString: value)
    }

    private func intValue(_ path: String, sql: String) throws -> Int {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else { return 0 }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }
}
