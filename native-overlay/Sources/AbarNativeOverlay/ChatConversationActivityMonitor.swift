import AbarOverlayCore
import Foundation

final class ChatConversationActivityMonitor {
    private let fileManager: FileManager
    private let supportPath: String
    private let activeWindow: TimeInterval
    private var activeFilePath: String?
    private var activeStartedAt: Date?

    init(
        fileManager: FileManager = .default,
        supportPath: String = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/com.openai.chat"),
        activeWindow: TimeInterval = 20
    ) {
        self.fileManager = fileManager
        self.supportPath = supportPath
        self.activeWindow = activeWindow
    }

    func currentTask(now: Date = Date()) -> AbarTaskSummary? {
        guard let latest = latestConversationFile(),
              now.timeIntervalSince(latest.modifiedAt) <= activeWindow
        else {
            activeFilePath = nil
            activeStartedAt = nil
            return nil
        }

        if activeFilePath != latest.path || activeStartedAt == nil {
            activeFilePath = latest.path
            activeStartedAt = min(latest.modifiedAt, now)
        }

        let startedAt = activeStartedAt ?? latest.modifiedAt
        let durationSeconds = max(0, Int(now.timeIntervalSince(startedAt)))
        return AbarTaskSummary(
            id: "chat-conversation:\(latest.path)",
            projectName: "ChatGPT",
            promptPreview: "对话中",
            startedAt: startedAt,
            lastActivityAt: latest.modifiedAt,
            durationSeconds: durationSeconds,
            completedAt: nil,
            transcriptPath: latest.path,
            sessionId: "chat-conversation",
            turnId: latest.path,
            state: .running
        )
    }

    private func latestConversationFile() -> ConversationFile? {
        guard let enumerator = fileManager.enumerator(
            atPath: supportPath
        ) else {
            return nil
        }

        var latest: ConversationFile?
        for case let relativePath as String in enumerator {
            guard relativePath.hasSuffix(".data"),
                  relativePath.contains("/conversations-v3-") || relativePath.hasPrefix("conversations-v3-")
            else {
                continue
            }

            let path = (supportPath as NSString).appendingPathComponent(relativePath)
            guard let modifiedAt = try? fileManager
                .attributesOfItem(atPath: path)[.modificationDate] as? Date
            else {
                continue
            }

            if latest == nil || modifiedAt > latest!.modifiedAt {
                latest = ConversationFile(path: path, modifiedAt: modifiedAt)
            }
        }
        return latest
    }
}

private struct ConversationFile {
    var path: String
    var modifiedAt: Date
}
