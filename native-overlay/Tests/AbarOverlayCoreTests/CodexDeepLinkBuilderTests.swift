import AbarOverlayCore
import XCTest

final class CodexDeepLinkBuilderTests: XCTestCase {
    func testBuildsThreadURLFromSessionID() {
        let task = task(sessionId: "019ed8af-cded-76a2-a9cc-c02bc1b74e40")

        XCTAssertEqual(
            CodexDeepLinkBuilder.threadURL(for: task)?.absoluteString,
            "codex://threads/019ed8af-cded-76a2-a9cc-c02bc1b74e40"
        )
    }

    func testDoesNotBuildThreadURLForMissingSessionID() {
        XCTAssertNil(CodexDeepLinkBuilder.threadURL(for: task(sessionId: "")))
        XCTAssertNil(CodexDeepLinkBuilder.threadURL(for: task(sessionId: "unknown-session")))
    }

    func testNavigationPlanAlwaysFallsBackToCodexBundle() {
        let plan = CodexTaskNavigationPlan.make(for: task(sessionId: "session-1"))

        XCTAssertEqual(plan.deepLinkURL?.absoluteString, "codex://threads/session-1")
        XCTAssertEqual(plan.fallbackBundleIdentifier, "com.openai.codex")
    }

    private func task(sessionId: String) -> AbarTaskSummary {
        AbarTaskSummary(
            id: "\(sessionId):turn-1",
            projectName: "Abar",
            promptPreview: "开始执行",
            startedAt: Date(timeIntervalSince1970: 0),
            lastActivityAt: Date(timeIntervalSince1970: 10),
            durationSeconds: 10,
            completedAt: Date(timeIntervalSince1970: 10),
            transcriptPath: "/tmp/session.jsonl",
            sessionId: sessionId,
            turnId: "turn-1",
            state: .completed
        )
    }
}
