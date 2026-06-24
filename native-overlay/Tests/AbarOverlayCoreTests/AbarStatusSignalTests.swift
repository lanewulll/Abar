import AbarOverlayCore
import XCTest

final class AbarStatusSignalTests: XCTestCase {
    func testRunningTaskProducesRunningSignal() {
        let signal = AbarStatusSignalResolver.signal(
            tasks: [task(state: .running)],
            events: [],
            now: Date(timeIntervalSince1970: 100),
            acknowledgedAt: nil
        )

        XCTAssertEqual(signal, .running)
    }

    func testErrorEventProducesInterruptedSignal() {
        let signal = AbarStatusSignalResolver.signal(
            tasks: [],
            events: [
                event(status: "error", createdAt: Date(timeIntervalSince1970: 100))
            ],
            now: Date(timeIntervalSince1970: 120),
            acknowledgedAt: nil
        )

        XCTAssertEqual(signal, .interrupted)
    }

    func testNormalStopDoesNotProduceInterruptedSignal() {
        let signal = AbarStatusSignalResolver.signal(
            tasks: [],
            events: [
                event(eventType: "Stop", status: "unknown", createdAt: Date(timeIntervalSince1970: 100))
            ],
            now: Date(timeIntervalSince1970: 120),
            acknowledgedAt: nil
        )

        XCTAssertEqual(signal, .idle)
    }

    func testCompletedTaskClearsOlderInterruptedSignal() {
        let signal = AbarStatusSignalResolver.signal(
            tasks: [task(state: .completed, lastActivityAt: Date(timeIntervalSince1970: 120))],
            events: [
                event(status: "error", createdAt: Date(timeIntervalSince1970: 100))
            ],
            now: Date(timeIntervalSince1970: 130),
            acknowledgedAt: nil
        )

        XCTAssertEqual(signal, .idle)
    }

    func testSuccessEventClearsOlderInterruptedSignal() {
        let signal = AbarStatusSignalResolver.signal(
            tasks: [],
            events: [
                event(status: "success", createdAt: Date(timeIntervalSince1970: 120)),
                event(status: "error", createdAt: Date(timeIntervalSince1970: 100))
            ],
            now: Date(timeIntervalSince1970: 130),
            acknowledgedAt: nil
        )

        XCTAssertEqual(signal, .idle)
    }

    func testToolInputTextDoesNotProduceInterruptedSignal() {
        let signal = AbarStatusSignalResolver.signal(
            tasks: [],
            events: [
                event(
                    eventType: "PreToolUse",
                    status: "unknown",
                    payloadJSON: #"{"tool_input":{"command":"echo interrupt abort cancel hook exited"}}"#,
                    createdAt: Date(timeIntervalSince1970: 100)
                )
            ],
            now: Date(timeIntervalSince1970: 120),
            acknowledgedAt: nil
        )

        XCTAssertEqual(signal, .idle)
    }

    func testInterruptedSignalReturnsToIdleAfterThreeMinutesOrAcknowledgement() {
        let interruptedEvent = event(status: "error", createdAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(
            AbarStatusSignalResolver.signal(
                tasks: [],
                events: [interruptedEvent],
                now: Date(timeIntervalSince1970: 281),
                acknowledgedAt: nil
            ),
            .idle
        )
        XCTAssertEqual(
            AbarStatusSignalResolver.signal(
                tasks: [],
                events: [interruptedEvent],
                now: Date(timeIntervalSince1970: 120),
                acknowledgedAt: Date(timeIntervalSince1970: 110)
            ),
            .idle
        )
    }

    func testAcknowledgementReturnsRunningSignalToIdleUntilNewActivity() {
        XCTAssertEqual(
            AbarStatusSignalResolver.signal(
                tasks: [task(state: .running)],
                events: [],
                now: Date(timeIntervalSince1970: 120),
                acknowledgedAt: Date(timeIntervalSince1970: 110)
            ),
            .idle
        )
        XCTAssertEqual(
            AbarStatusSignalResolver.signal(
                tasks: [task(state: .running)],
                events: [
                    event(status: "success", createdAt: Date(timeIntervalSince1970: 130))
                ],
                now: Date(timeIntervalSince1970: 140),
                acknowledgedAt: Date(timeIntervalSince1970: 110)
            ),
            .running
        )
    }

    private func task(
        state: AbarTaskState,
        lastActivityAt: Date = Date(timeIntervalSince1970: 100)
    ) -> AbarTaskSummary {
        AbarTaskSummary(
            id: "session:turn",
            projectName: "Abar",
            promptPreview: "测试任务",
            startedAt: Date(timeIntervalSince1970: 90),
            lastActivityAt: lastActivityAt,
            durationSeconds: 10,
            completedAt: state == .completed ? lastActivityAt : nil,
            transcriptPath: nil,
            sessionId: "session",
            turnId: "turn",
            state: state
        )
    }

    private func event(
        eventType: String = "PostToolUse",
        status: String,
        payloadJSON: String? = nil,
        createdAt: Date
    ) -> AbarEventSummary {
        AbarEventSummary(
            id: UUID().uuidString,
            eventType: eventType,
            toolName: nil,
            status: status,
            payloadJSON: payloadJSON,
            createdAt: createdAt
        )
    }
}
