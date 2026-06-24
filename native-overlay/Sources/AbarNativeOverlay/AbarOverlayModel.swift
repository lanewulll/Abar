import AbarOverlayCore
import AppKit
import Foundation

@MainActor
final class AbarOverlayModel: ObservableObject {
    @Published private(set) var snapshot: AbarSnapshot = .empty()
    @Published private(set) var errorMessage: String?
    @Published private(set) var isExpanded = false
    @Published private(set) var clockNow = Date()

    private let taskNavigator = TaskNavigator()
    private let databasePath: String
    private let snapshotQueue = DispatchQueue(label: "dev.abar.native-overlay.snapshot", qos: .userInitiated)
    private let onCompletionPulse: () -> Void
    private let onTaskJump: () -> Void
    private let onStateChanged: (AbarStatusSignal) -> Void
    private var completionPulseDetector = AbarTaskCompletionPulseDetector()
    private var acknowledgedAt: Date?
    private var refreshGate = AbarRefreshGate()
    private var snapshotTimer: Timer?
    private var clockTimer: Timer?

    init(
        databasePath: String = AbarOverlayModel.defaultDatabasePath(),
        onCompletionPulse: @escaping () -> Void = {},
        onTaskJump: @escaping () -> Void = {},
        onStateChanged: @escaping (AbarStatusSignal) -> Void = { _ in }
    ) {
        self.databasePath = databasePath
        self.onCompletionPulse = onCompletionPulse
        self.onTaskJump = onTaskJump
        self.onStateChanged = onStateChanged
    }

    var displayedTasks: [AbarTaskSummary] {
        snapshot.tasks
    }

    var displayedActivityState: AbarActivityState {
        displayedTasks.contains(where: { $0.state == .running }) ? .working : .idle
    }

    var displayedStatusSignal: AbarStatusSignal {
        AbarStatusSignalResolver.signal(
            tasks: displayedTasks,
            events: snapshot.recentEvents,
            now: clockNow,
            acknowledgedAt: acknowledgedAt
        )
    }

    func start() {
        tickClock()
        refresh()
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: AbarSamplingPolicy.snapshotRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickClock()
            }
        }
    }

    func stop() {
        snapshotTimer?.invalidate()
        clockTimer?.invalidate()
        snapshotTimer = nil
        clockTimer = nil
    }

    func refresh() {
        guard refreshGate.begin() else { return }
        let databasePath = databasePath
        snapshotQueue.async {
            let result = Result {
                try AbarDatabaseReader(databasePath: databasePath).loadSnapshot()
            }
            Task { @MainActor [weak self] in
                self?.finishRefresh(result)
            }
        }
    }

    private func finishRefresh(_ result: Result<AbarSnapshot, Error>) {
        defer { refreshGate.finish() }
        switch result {
        case let .success(loadedSnapshot):
            snapshot = loadedSnapshot
            errorMessage = nil
            if !completionPulseDetector.newCompletionIDs(in: loadedSnapshot.tasks).isEmpty {
                onCompletionPulse()
            }
        case let .failure(error):
            errorMessage = "Waiting for Abar data at \(databasePath): \(error)"
        }
        onStateChanged(displayedStatusSignal)
    }

    private func tickClock() {
        clockNow = Date()
        onStateChanged(displayedStatusSignal)
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
    }

    func activate(task: AbarTaskSummary) {
        taskNavigator.activate(task: task)
        acknowledgedAt = Date()
        onStateChanged(displayedStatusSignal)
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
