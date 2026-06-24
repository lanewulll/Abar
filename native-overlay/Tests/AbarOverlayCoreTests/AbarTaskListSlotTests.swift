import AbarOverlayCore
import XCTest

final class AbarTaskListSlotTests: XCTestCase {
    func testAlwaysBuildsFourTaskListSlots() {
        XCTAssertEqual(AbarTaskListSlots.make(tasks: []).count, 4)
        XCTAssertEqual(AbarTaskListSlots.make(tasks: [task(id: "1")]).count, 4)
        XCTAssertEqual(AbarTaskListSlots.make(tasks: [task(id: "1"), task(id: "2"), task(id: "3"), task(id: "4"), task(id: "5")]).count, 4)
    }

    func testPlacesTasksInOrderThenEmptySlots() {
        let slots = AbarTaskListSlots.make(tasks: [task(id: "1"), task(id: "2")])

        XCTAssertEqual(slots.compactMap(\.task?.id), ["1", "2"])
        XCTAssertTrue(slots[2].isEmpty)
        XCTAssertTrue(slots[3].isEmpty)
    }

    func testHidesTasksAfterFourthSlot() {
        let slots = AbarTaskListSlots.make(tasks: [
            task(id: "1"),
            task(id: "2"),
            task(id: "3"),
            task(id: "4"),
            task(id: "5")
        ])

        XCTAssertEqual(slots.compactMap(\.task?.id), ["1", "2", "3", "4"])
    }

    private func task(id: String) -> AbarTaskSummary {
        AbarTaskSummary(
            id: id,
            projectName: "Abar",
            promptPreview: "任务",
            startedAt: Date(timeIntervalSince1970: 100),
            lastActivityAt: Date(timeIntervalSince1970: 120),
            durationSeconds: 20,
            completedAt: Date(timeIntervalSince1970: 120),
            transcriptPath: nil,
            sessionId: "session-\(id)",
            turnId: "turn-\(id)",
            state: .completed
        )
    }
}
