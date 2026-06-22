import AbarOverlayCore
import XCTest

final class AbarTaskCompletionPulseTests: XCTestCase {
    func testReturnsOnlyNewlyCompletedTaskIDs() {
        var detector = AbarTaskCompletionPulseDetector()
        let running = task(id: "session:turn", state: .running)
        let completed = task(id: "session:turn", state: .completed)

        XCTAssertEqual(detector.newCompletionIDs(in: [running]), [])
        XCTAssertEqual(detector.newCompletionIDs(in: [completed]), ["session:turn"])
        XCTAssertEqual(detector.newCompletionIDs(in: [completed]), [])
    }

    private func task(id: String, state: AbarTaskState) -> AbarTaskSummary {
        AbarTaskSummary(
            id: id,
            projectName: "Abar",
            promptPreview: "测试任务",
            startedAt: Date(timeIntervalSince1970: 100),
            lastActivityAt: Date(timeIntervalSince1970: 160),
            durationSeconds: 60,
            completedAt: state == .completed ? Date(timeIntervalSince1970: 160) : nil,
            transcriptPath: nil,
            sessionId: "session",
            turnId: "turn",
            state: state
        )
    }
}
