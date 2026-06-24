import Foundation

public enum CodexDeepLinkBuilder {
    public static func threadURL(for task: AbarTaskSummary) -> URL? {
        threadURL(sessionId: task.sessionId)
    }

    public static func threadURL(sessionId: String) -> URL? {
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "unknown-session" else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/" + trimmed
        return components.url
    }
}

public struct CodexTaskNavigationPlan: Equatable {
    public static let codexBundleIdentifier = "com.openai.codex"

    public var deepLinkURL: URL?
    public var fallbackBundleIdentifier: String

    public init(deepLinkURL: URL?, fallbackBundleIdentifier: String = Self.codexBundleIdentifier) {
        self.deepLinkURL = deepLinkURL
        self.fallbackBundleIdentifier = fallbackBundleIdentifier
    }

    public static func make(for task: AbarTaskSummary) -> CodexTaskNavigationPlan {
        CodexTaskNavigationPlan(deepLinkURL: CodexDeepLinkBuilder.threadURL(for: task))
    }
}
