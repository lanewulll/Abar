import AbarOverlayCore
@testable import AbarNativeOverlay
import XCTest

@MainActor
final class AbarMaintenanceServiceTests: XCTestCase {
    func testCurrentProjectPathReadsLatestPersistedHookPath() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-maintenance-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let store = AbarEventStore(databasePath: dbURL.path)
        try store.initialize(defaultPort: 3987)
        let service = AbarMaintenanceService(
            store: store,
            fallbackProjectPath: "/tmp/startup",
            onChanged: {}
        )

        XCTAssertEqual(service.currentProjectPath(), "/tmp/startup")

        try store.insertEvent(
            AbarStoredEvent(
                id: "event-1",
                eventType: "UserPromptSubmit",
                projectPath: "/tmp/latest-project",
                sessionId: "session",
                toolName: nil,
                toolUseId: nil,
                status: "unknown",
                payloadJSON: "{}",
                createdAt: "2026-06-22T01:00:00.000Z"
            )
        )

        XCTAssertEqual(service.currentProjectPath(), "/tmp/latest-project")
    }
}
