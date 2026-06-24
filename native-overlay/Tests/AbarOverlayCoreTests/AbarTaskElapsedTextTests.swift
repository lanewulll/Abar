import AbarOverlayCore
import XCTest

final class AbarTaskElapsedTextTests: XCTestCase {
    func testRunningTaskUsesCurrentClockInsteadOfStoredDuration() {
        let task = makeTask(
            state: .running,
            startedAt: Date(timeIntervalSince1970: 100),
            lastActivityAt: Date(timeIntervalSince1970: 100),
            durationSeconds: 0,
            completedAt: nil
        )

        XCTAssertEqual(
            AbarTaskElapsedText.text(for: task, now: Date(timeIntervalSince1970: 120)),
            "20s"
        )
    }

    func testCompletedTaskUsesFixedDuration() {
        let task = makeTask(
            state: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            lastActivityAt: Date(timeIntervalSince1970: 130),
            durationSeconds: 30,
            completedAt: Date(timeIntervalSince1970: 130)
        )

        XCTAssertEqual(
            AbarTaskElapsedText.text(for: task, now: Date(timeIntervalSince1970: 1_000)),
            "30s"
        )
    }

    private func makeTask(
        state: AbarTaskState,
        startedAt: Date,
        lastActivityAt: Date,
        durationSeconds: Int,
        completedAt: Date?
    ) -> AbarTaskSummary {
        AbarTaskSummary(
            id: "session:turn",
            projectName: "Abar",
            promptPreview: "任务",
            startedAt: startedAt,
            lastActivityAt: lastActivityAt,
            durationSeconds: durationSeconds,
            completedAt: completedAt,
            transcriptPath: nil,
            sessionId: "session",
            turnId: "turn",
            state: state
        )
    }
}
