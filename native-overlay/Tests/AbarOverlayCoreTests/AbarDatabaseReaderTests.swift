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
                INSERT INTO app_config VALUES ('project_path', '/Users/example/Desktop/codex/Abar', '2026-06-22T00:00:00.000Z');
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
        XCTAssertEqual(snapshot.projectPath, "/Users/example/Desktop/codex/Abar")
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
                projectPath: "/Users/example/Desktop/codex/Abar",
                sessionId: "session-1",
                payloadJSON: """
                {"prompt":"修复菜单栏显示问题并验证","cwd":"/Users/example/Desktop/codex/Abar","session_id":"session-1","turn_id":"turn-1","transcript_path":"/tmp/session-1.jsonl"}
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
        XCTAssertEqual(snapshot.tasks.first?.promptPreview, "修复菜单栏显示问题并验证")
        XCTAssertEqual(snapshot.tasks.first?.sessionId, "session-1")
        XCTAssertEqual(snapshot.tasks.first?.turnId, "turn-1")
        XCTAssertEqual(snapshot.tasks.first?.transcriptPath, "/tmp/session-1.jsonl")
        XCTAssertEqual(snapshot.tasks.first?.state, .running)
        XCTAssertEqual(snapshot.tasks.first?.startedAt, Self.date("2026-06-22T01:00:00.000Z"))
        XCTAssertEqual(snapshot.tasks.first?.lastActivityAt, Self.date("2026-06-22T01:00:00.000Z"))
        XCTAssertEqual(snapshot.tasks.first?.durationSeconds, 0)
        XCTAssertNil(snapshot.tasks.first?.completedAt)
    }

    func testSnapshotUsesApiBaseURLFromRecentHookPayload() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertEvent(
                db,
                id: "prompt-api",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-api",
                payloadJSON: """
                {"prompt":"使用 API","cwd":"/tmp/ProjectA","session_id":"session-api","turn_id":"turn-api","abar_connection":{"mode":"api","baseUrl":"https://gateway.example.com/v1","hasApiKey":true}}
                """,
                createdAt: "2026-06-22T01:00:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            codexHome: temporaryDirectoryURL().path,
            now: { Self.date("2026-06-22T01:01:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.codexConnection.mode, .api)
        XCTAssertEqual(snapshot.codexConnection.displayText, "https://gateway.example.com/v1")
    }

    func testSnapshotUsesEmailFromAuthWhenHookIsAccountMode() throws {
        let dbURL = temporaryDatabaseURL()
        let codexHome = temporaryDirectoryURL()
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try """
        {"auth_mode":"chatgpt","tokens":{"id_token":"\(Self.jwt(payload: #"{"email":"user@example.com"}"#))"}}
        """.write(to: codexHome.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertEvent(
                db,
                id: "prompt-account",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-account",
                payloadJSON: """
                {"prompt":"使用官方账号","cwd":"/tmp/ProjectA","session_id":"session-account","turn_id":"turn-account","abar_connection":{"mode":"account","hasApiKey":false}}
                """,
                createdAt: "2026-06-22T01:00:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            codexHome: codexHome.path,
            now: { Self.date("2026-06-22T01:01:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.codexConnection.mode, .account)
        XCTAssertEqual(snapshot.codexConnection.displayText, "user@example.com")
    }

    func testIgnoresInternalSuggestionPromptWhenDerivingTasks() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertPromptAndStop(
                db,
                projectPath: "/Users/example/Desktop/codex/redskill",
                sessionId: "real-session",
                turnId: "real-turn",
                prompt: "你好",
                promptAt: "2026-06-23T08:38:30.000Z",
                stopAt: "2026-06-23T08:38:36.000Z"
            )
            insertEvent(
                db,
                id: "suggestion-prompt",
                eventType: "UserPromptSubmit",
                projectPath: "/Users/example/Desktop/codex/redskill",
                sessionId: "suggestion-session",
                payloadJSON: """
                {"prompt":"# Overview\\n\\nGenerate 0 to 3 hyperpersonalized suggestions for what this user can do with Codex in this local project: /Users/example/Desktop/codex/redskill\\n\\n# Rules","cwd":"/Users/example/Desktop/codex/redskill","session_id":"suggestion-session","turn_id":"suggestion-turn","transcript_path":null}
                """,
                createdAt: "2026-06-23T08:38:42.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-23T08:39:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks.map(\.id), ["real-session:real-turn"])
        XCTAssertEqual(snapshot.tasks.first?.promptPreview, "你好")
        XCTAssertEqual(snapshot.tasks.first?.state, .completed)
        XCTAssertEqual(snapshot.activityState, .idle)
    }

    func testIgnoresAmbientSafetyPromptWhenDerivingTasks() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertEvent(
                db,
                id: "safety-prompt",
                eventType: "UserPromptSubmit",
                projectPath: "/",
                sessionId: "ambient-session",
                payloadJSON: """
                {"prompt":"You are an expert at upholding safety and compliance standards for Codex ambient suggestions.\\n\\nThen, I will show you a list of ambient suggestion candidates.\\n\\nYour task is to determine if any suggestions should be excluded.","cwd":"/","session_id":"ambient-session","turn_id":"ambient-turn","transcript_path":null,"model":"gpt-5.4-mini"}
                """,
                createdAt: "2026-06-23T08:42:56.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-23T08:45:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks, [])
        XCTAssertEqual(snapshot.activityState, .idle)
    }

    func testKeepsRootDirectoryUserPromptWhenDerivingTasks() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertEvent(
                db,
                id: "root-prompt",
                eventType: "UserPromptSubmit",
                projectPath: "/",
                sessionId: "root-session",
                payloadJSON: """
                {"prompt":"请检查根目录下的临时日志","cwd":"/","session_id":"root-session","turn_id":"root-turn","transcript_path":"/tmp/root-session.jsonl"}
                """,
                createdAt: "2026-06-23T09:00:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-23T09:01:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks.map(\.id), ["root-session:root-turn"])
        XCTAssertEqual(snapshot.tasks.first?.promptPreview, "请检查根目录下的临时日志")
        XCTAssertEqual(snapshot.tasks.first?.state, .running)
        XCTAssertEqual(snapshot.activityState, .working)
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

    func testPromptPreviewUsesMyRequestSectionWhenFilesArePresent() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertEvent(
                db,
                id: "prompt-1",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-1",
                payloadJSON: #"""
                {
                  "prompt": "\n# Files mentioned by the user:\n\n## codex-clipboard.png: /tmp/codex-clipboard.png\n\n## My request for Codex:\n这个位置要改成user prompt的部分\n",
                  "cwd": "/tmp/ProjectA",
                  "session_id": "session-1",
                  "turn_id": "turn-1",
                  "transcript_path": "/tmp/session-1.jsonl"
                }
                """#,
                createdAt: "2026-06-22T01:00:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T01:01:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks.first?.promptPreview, "这个位置要改成userprom...")
    }

    func testPlanPromptPreviewUsesMarkdownTitle() throws {
        try assertPromptPreview(
            for: """
            PLEASE IMPLEMENT THIS PLAN:
            # 移除面板底角阴影

            **Summary**
            - 删除面板阴影。
            """,
            equals: "移除面板底角阴影"
        )
    }

    func testPlanPromptPreviewTruncatesLongMarkdownTitle() throws {
        try assertPromptPreview(
            for: """
            PLEASE IMPLEMENT THIS PLAN:
            # Abar 面板紧凑版压缩计划与视觉验证
            """,
            equals: "Abar面板紧凑版压缩计划与视..."
        )
    }

    func testPlanPromptPreviewFallsBackWhenTitleIsMissing() throws {
        try assertPromptPreview(
            for: """
            PLEASE IMPLEMENT THIS PLAN:

            **Summary**
            - 执行计划。
            """,
            equals: "执行计划模式计划"
        )
    }

    func testPlanPromptPreviewDoesNotUseSecondaryHeadingAsTitle() throws {
        try assertPromptPreview(
            for: """
            PLEASE IMPLEMENT THIS PLAN:

            ## Summary
            - 执行计划。
            """,
            equals: "执行计划模式计划"
        )
    }

    func testPromptPreviewDoesNotTreatPlanMarkerInBodyAsPrefix() throws {
        try assertPromptPreview(
            for: "正文 PLEASE IMPLEMENT THIS PLAN: 不是前缀",
            equals: "正文PLEASEIMPLEME..."
        )
    }

    func testKeepsUnclosedCurrentDayPromptRunningAfterThirtyMinutesWithoutToolEvents() throws {
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
                {"prompt":"长时间代码审查","cwd":"/tmp/ProjectA","session_id":"session-1","turn_id":"turn-1","transcript_path":"/tmp/session-1.jsonl"}
                """,
                createdAt: "2026-06-22T01:00:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T01:31:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks.map(\.id), ["session-1:turn-1"])
        XCTAssertEqual(snapshot.tasks.first?.state, .running)
        XCTAssertEqual(snapshot.activityState, .working)
    }

    func testHidesStaleUnclosedPromptWhenSameProjectHasNewerPrompt() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertEvent(
                db,
                id: "prompt-old",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-old",
                payloadJSON: """
                {"prompt":"旧的缺 Stop 任务","cwd":"/tmp/ProjectA","session_id":"session-old","turn_id":"turn-old","transcript_path":"/tmp/session-old.jsonl"}
                """,
                createdAt: "2026-06-22T01:00:00.000Z"
            )
            insertEvent(
                db,
                id: "prompt-new",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-new",
                payloadJSON: """
                {"prompt":"新的项目任务","cwd":"/tmp/ProjectA","session_id":"session-new","turn_id":"turn-new","transcript_path":"/tmp/session-new.jsonl"}
                """,
                createdAt: "2026-06-22T01:20:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T01:21:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks.map(\.id), ["session-new:turn-new"])
        XCTAssertEqual(snapshot.tasks.first?.state, .running)
        XCTAssertEqual(snapshot.activityState, .working)
    }

    func testKeepsRecentlyActiveUnclosedPromptWhenSameProjectHasNewerPrompt() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertEvent(
                db,
                id: "prompt-old",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-old",
                payloadJSON: """
                {"prompt":"仍在工作","cwd":"/tmp/ProjectA","session_id":"session-old","turn_id":"turn-old","transcript_path":"/tmp/session-old.jsonl"}
                """,
                createdAt: "2026-06-22T01:00:00.000Z"
            )
            insertEvent(
                db,
                id: "tool-old",
                eventType: "PostToolUse",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-old",
                payloadJSON: """
                {"cwd":"/tmp/ProjectA","session_id":"session-old","turn_id":"turn-old","tool_name":"Bash"}
                """,
                createdAt: "2026-06-22T01:19:30.000Z"
            )
            insertEvent(
                db,
                id: "prompt-new",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-new",
                payloadJSON: """
                {"prompt":"新的项目任务","cwd":"/tmp/ProjectA","session_id":"session-new","turn_id":"turn-new","transcript_path":"/tmp/session-new.jsonl"}
                """,
                createdAt: "2026-06-22T01:20:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T01:21:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks.map(\.id), ["session-new:turn-new", "session-old:turn-old"])
        XCTAssertEqual(snapshot.tasks.map(\.state), [.running, .running])
        XCTAssertEqual(snapshot.tasks.last?.lastActivityAt, Self.date("2026-06-22T01:19:30.000Z"))
    }

    func testHidesOlderUnclosedPromptWhenSameSessionStartsNewPrompt() throws {
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
                {"prompt":"旧的未关闭任务","cwd":"/tmp/ProjectA","session_id":"session-1","turn_id":"turn-1","transcript_path":"/tmp/session-1.jsonl"}
                """,
                createdAt: "2026-06-22T01:00:00.000Z"
            )
            insertEvent(
                db,
                id: "prompt-2",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-1",
                payloadJSON: """
                {"prompt":"新的运行任务","cwd":"/tmp/ProjectA","session_id":"session-1","turn_id":"turn-2","transcript_path":"/tmp/session-1.jsonl"}
                """,
                createdAt: "2026-06-22T01:10:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T01:30:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks.map(\.id), ["session-1:turn-2"])
        XCTAssertEqual(snapshot.tasks.first?.state, .running)
        XCTAssertEqual(snapshot.activityState, .working)
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

    func testStopWithDifferentTurnCompletesLatestOpenPromptInSameSession() throws {
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
                {"prompt":"开始执行长任务","cwd":"/tmp/ProjectA","session_id":"session-1","turn_id":"prompt-turn","transcript_path":"/tmp/session-1.jsonl"}
                """,
                createdAt: "2026-06-22T01:00:00.000Z"
            )
            insertEvent(
                db,
                id: "stop-1",
                eventType: "Stop",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-1",
                payloadJSON: """
                {"cwd":"/tmp/ProjectA","session_id":"session-1","turn_id":"stop-turn","transcript_path":"/tmp/session-1.jsonl"}
                """,
                createdAt: "2026-06-22T01:30:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T01:31:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.activityState, .idle)
        XCTAssertEqual(snapshot.tasks.map(\.id), ["session-1:prompt-turn"])
        XCTAssertEqual(snapshot.tasks.first?.state, .completed)
        XCTAssertEqual(snapshot.tasks.first?.completedAt, Self.date("2026-06-22T01:30:00.000Z"))
        XCTAssertEqual(snapshot.tasks.first?.durationSeconds, 1_800)
    }

    func testKeepsCompletedTasksForCurrentDay() throws {
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
            now: { Self.date("2026-06-22T12:00:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks.map(\.id), ["session-1:turn-1"])
        XCTAssertEqual(snapshot.tasks.first?.state, .completed)
        XCTAssertEqual(snapshot.activityState, .idle)
    }

    func testHidesCompletedTasksFromPreviousDay() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertPromptAndStop(
                db,
                projectPath: "/tmp/ProjectA",
                sessionId: "session-1",
                turnId: "turn-1",
                prompt: "昨天完成",
                promptAt: "2026-06-21T11:58:00.000Z",
                stopAt: "2026-06-21T12:00:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T12:00:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks, [])
        XCTAssertEqual(snapshot.activityState, .idle)
    }

    func testKeepsOlderCompletedTaskWhenSameProjectStartsNewTask() throws {
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

        XCTAssertEqual(snapshot.tasks.map(\.id), ["session-2:turn-2", "session-1:turn-1"])
        XCTAssertEqual(snapshot.tasks.first?.state, .running)
        XCTAssertEqual(snapshot.tasks.last?.state, .completed)
        XCTAssertEqual(snapshot.activityState, .working)
    }

    func testReturnsOnlyFourMostRecentCompletedTasksForCurrentDay() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            for index in 1...5 {
                insertPromptAndStop(
                    db,
                    projectPath: "/tmp/ProjectA",
                    sessionId: "session-\(index)",
                    turnId: "turn-\(index)",
                    prompt: "任务\(index)",
                    promptAt: "2026-06-22T01:0\(index):00.000Z",
                    stopAt: "2026-06-22T01:0\(index):30.000Z"
                )
            }
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T12:00:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks.map(\.id), [
            "session-5:turn-5",
            "session-4:turn-4",
            "session-3:turn-3",
            "session-2:turn-2"
        ])
    }

    func testCompletedHistorySurvivesNoisyToolEvents() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            for index in 1...4 {
                insertPromptAndStop(
                    db,
                    projectPath: "/tmp/ProjectA",
                    sessionId: "session-\(index)",
                    turnId: "turn-\(index)",
                    prompt: "历史任务\(index)",
                    promptAt: "2026-06-22T01:0\(index):00.000Z",
                    stopAt: "2026-06-22T01:0\(index):30.000Z"
                )
            }
            for index in 1...130 {
                insertEvent(
                    db,
                    id: "tool-\(index)",
                    eventType: "PostToolUse",
                    projectPath: "/tmp/ProjectA",
                    sessionId: "session-noise",
                    payloadJSON: """
                    {"cwd":"/tmp/ProjectA","session_id":"session-noise","turn_id":"turn-noise","tool_name":"Bash"}
                    """,
                    createdAt: String(format: "2026-06-22T02:%02d:%02d.000Z", index / 60, index % 60)
                )
            }
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T12:00:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks.map(\.id), [
            "session-4:turn-4",
            "session-3:turn-3",
            "session-2:turn-2",
            "session-1:turn-1"
        ])
    }

    func testRunningTasksAreShownBeforeCompletedHistoryAndLimitedToFourRows() throws {
        let dbURL = temporaryDatabaseURL()
        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            for index in 1...4 {
                insertPromptAndStop(
                    db,
                    projectPath: "/tmp/ProjectA",
                    sessionId: "session-\(index)",
                    turnId: "turn-\(index)",
                    prompt: "完成\(index)",
                    promptAt: "2026-06-22T01:0\(index):00.000Z",
                    stopAt: "2026-06-22T01:0\(index):30.000Z"
                )
            }
            insertEvent(
                db,
                id: "prompt-running",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/ProjectB",
                sessionId: "session-running",
                payloadJSON: """
                {"prompt":"正在运行","cwd":"/tmp/ProjectB","session_id":"session-running","turn_id":"turn-running","transcript_path":"/tmp/session-running.jsonl"}
                """,
                createdAt: "2026-06-22T01:02:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T01:03:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks.count, 4)
        XCTAssertEqual(snapshot.tasks.first?.id, "session-running:turn-running")
        XCTAssertEqual(snapshot.tasks.first?.state, .running)
        XCTAssertEqual(snapshot.tasks.dropFirst().map(\.id), [
            "session-4:turn-4",
            "session-3:turn-3",
            "session-2:turn-2"
        ])
        XCTAssertEqual(snapshot.activityState, .working)
    }

    private func assertPromptPreview(
        for prompt: String,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let dbURL = temporaryDatabaseURL()
        let payloadData = try JSONSerialization.data(withJSONObject: [
            "prompt": prompt,
            "cwd": "/tmp/ProjectA",
            "session_id": "session-preview",
            "turn_id": "turn-preview",
            "transcript_path": "/tmp/session-preview.jsonl"
        ])
        let payloadJSON = String(decoding: payloadData, as: UTF8.self)

        try withSQLiteDatabase(at: dbURL.path) { db in
            createReaderSchema(db)
            insertEvent(
                db,
                id: "prompt-preview",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/ProjectA",
                sessionId: "session-preview",
                payloadJSON: payloadJSON,
                createdAt: "2026-06-22T01:00:00.000Z"
            )
        }

        let reader = AbarDatabaseReader(
            databasePath: dbURL.path,
            now: { Self.date("2026-06-22T01:01:00.000Z") }
        )
        let snapshot = try reader.loadSnapshot()

        XCTAssertEqual(snapshot.tasks.first?.promptPreview, expected, file: file, line: line)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-native-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-native-\(UUID().uuidString)", isDirectory: true)
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

    private static func jwt(payload: String) -> String {
        [
            base64URL(#"{"alg":"none"}"#),
            base64URL(payload),
            "signature"
        ].joined(separator: ".")
    }

    private static func base64URL(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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
