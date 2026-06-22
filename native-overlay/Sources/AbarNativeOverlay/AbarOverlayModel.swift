import AbarOverlayCore
import AppKit
import Foundation

@MainActor
final class AbarOverlayModel: ObservableObject {
    @Published private(set) var snapshot: AbarSnapshot = .empty()
    @Published private(set) var conversationTask: AbarTaskSummary?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isExpanded = false

    private let reader: AbarDatabaseReader
    private let conversationMonitor = ChatConversationActivityMonitor()
    private let taskNavigator = TaskNavigator()
    private let databasePath: String
    private let onCompletionPulse: () -> Void
    private let onTaskJump: () -> Void
    private let onStateChanged: (AbarActivityState) -> Void
    private var completionPulseDetector = AbarTaskCompletionPulseDetector()
    private var timer: Timer?

    init(
        databasePath: String = AbarOverlayModel.defaultDatabasePath(),
        onCompletionPulse: @escaping () -> Void = {},
        onTaskJump: @escaping () -> Void = {},
        onStateChanged: @escaping (AbarActivityState) -> Void = { _ in }
    ) {
        self.databasePath = databasePath
        self.onCompletionPulse = onCompletionPulse
        self.onTaskJump = onTaskJump
        self.onStateChanged = onStateChanged
        reader = AbarDatabaseReader(databasePath: databasePath)
    }

    var displayedTasks: [AbarTaskSummary] {
        if snapshot.tasks.contains(where: { $0.state == .running }) {
            return snapshot.tasks
        }
        if let conversationTask {
            return [conversationTask] + snapshot.tasks
        }
        return snapshot.tasks
    }

    var displayedActivityState: AbarActivityState {
        displayedTasks.contains(where: { $0.state == .running }) ? .working : .idle
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        do {
            let loadedSnapshot = try reader.loadSnapshot()
            snapshot = loadedSnapshot
            errorMessage = nil
            if !completionPulseDetector.newCompletionIDs(in: loadedSnapshot.tasks).isEmpty {
                onCompletionPulse()
            }
        } catch {
            errorMessage = "Waiting for Abar data at \(databasePath): \(error)"
        }
        conversationTask = conversationMonitor.currentTask()
        onStateChanged(displayedActivityState)
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
    }

    func activate(task: AbarTaskSummary) {
        taskNavigator.activate(task: task)
        onTaskJump()
    }

    static func defaultDatabasePath() -> String {
        let override = ProcessInfo.processInfo.environment["ABAR_NATIVE_DB_PATH"] ?? ""
        if !override.isEmpty {
            return override
        }

        return (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/abar/abar.sqlite")
    }
}
