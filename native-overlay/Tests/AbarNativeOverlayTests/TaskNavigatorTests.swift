import AbarOverlayCore
@testable import AbarNativeOverlay
import XCTest

@MainActor
final class TaskNavigatorTests: XCTestCase {
    func testOpensDeepLinkThenActivatesCodex() {
        var openedURLs: [URL] = []
        var activatedBundles: [String] = []
        let navigator = TaskNavigator(
            openDeepLink: { url in
                openedURLs.append(url)
                return true
            },
            activateBundle: { bundleIdentifier in
                activatedBundles.append(bundleIdentifier)
                return true
            }
        )

        navigator.activate(task: task(sessionId: "session-1"))

        XCTAssertEqual(openedURLs.map(\.absoluteString), ["codex://threads/session-1"])
        XCTAssertEqual(activatedBundles, ["com.openai.codex"])
    }

    func testFallsBackToCodexWhenDeepLinkOpenFails() {
        var openedURLs: [URL] = []
        var activatedBundles: [String] = []
        let navigator = TaskNavigator(
            openDeepLink: { url in
                openedURLs.append(url)
                return false
            },
            activateBundle: { bundleIdentifier in
                activatedBundles.append(bundleIdentifier)
                return true
            }
        )

        navigator.activate(task: task(sessionId: "session-1"))

        XCTAssertEqual(openedURLs.map(\.absoluteString), ["codex://threads/session-1"])
        XCTAssertEqual(activatedBundles, ["com.openai.codex"])
    }

    func testFallsBackToCodexWhenDeepLinkCannotBeBuilt() {
        var openedURLs: [URL] = []
        var activatedBundles: [String] = []
        let navigator = TaskNavigator(
            openDeepLink: { url in
                openedURLs.append(url)
                return true
            },
            activateBundle: { bundleIdentifier in
                activatedBundles.append(bundleIdentifier)
                return true
            }
        )

        navigator.activate(task: task(sessionId: "unknown-session"))

        XCTAssertEqual(openedURLs, [])
        XCTAssertEqual(activatedBundles, ["com.openai.codex"])
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
