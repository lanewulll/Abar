import AbarOverlayCore
import XCTest

final class AbarEventStoreTests: XCTestCase {
    func testNormalizesHookPayloadAndRedactsSensitiveFields() throws {
        let payload = Data(
            """
            {
              "id": "event-1",
              "hook_event_name": "PostToolUse",
              "tool_name": "Bash",
              "status": "success",
              "cwd": "/tmp/project",
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
        XCTAssertTrue(event.payloadJSON.contains(#""authorization":"[redacted]""#))
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
                {"provider":"codex","source":"internal_web_api","confidence":"high","windows":[{"name":"5h","usedPercent":11},{"name":"weekly","usedPercent":22}],"updatedAt":"2026-06-22T01:00:00.000Z"}
                """,
                error: nil
            )
        )

        let snapshot = try AbarDatabaseReader(databasePath: dbURL.path).loadSnapshot()

        XCTAssertEqual(snapshot.skillsCount, 1)
        XCTAssertEqual(snapshot.fiveHour.usedPercent, 11)
        XCTAssertEqual(snapshot.weekly.usedPercent, 22)
    }
}
