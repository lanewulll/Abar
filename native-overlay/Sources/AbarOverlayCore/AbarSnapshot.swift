import Foundation

public struct AbarSnapshot: Equatable {
    public var fiveHour: QuotaWindowSummary
    public var weekly: QuotaWindowSummary
    public var skillsCount: Int
    public var eventsCount: Int
    public var recentEvents: [AbarEventSummary]
    public var tasks: [AbarTaskSummary]
    public var codexConnection: AbarCodexConnectionSummary
    public var projectPath: String?
    public var loadedAt: Date

    public var activityState: AbarActivityState {
        tasks.contains(where: { $0.state == .running }) ? .working : .idle
    }

    public init(
        fiveHour: QuotaWindowSummary,
        weekly: QuotaWindowSummary,
        skillsCount: Int,
        eventsCount: Int,
        recentEvents: [AbarEventSummary],
        tasks: [AbarTaskSummary] = [],
        codexConnection: AbarCodexConnectionSummary = .unknown,
        projectPath: String?,
        loadedAt: Date
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.skillsCount = skillsCount
        self.eventsCount = eventsCount
        self.recentEvents = recentEvents
        self.tasks = tasks
        self.codexConnection = codexConnection
        self.projectPath = projectPath
        self.loadedAt = loadedAt
    }

    public static func empty(now: Date = Date()) -> AbarSnapshot {
        AbarSnapshot(
            fiveHour: .unavailable(name: "5h"),
            weekly: .unavailable(name: "Weekly"),
            skillsCount: 0,
            eventsCount: 0,
            recentEvents: [],
            tasks: [],
            codexConnection: .unknown,
            projectPath: nil,
            loadedAt: now
        )
    }
}

public enum AbarActivityState: Equatable {
    case idle
    case working
}

public enum AbarStatusSignal: Equatable {
    case idle
    case running
    case interrupted
}

public struct QuotaWindowSummary: Equatable {
    public var name: String
    public var usedPercent: Int?
    public var remainingPercent: Int?
    public var resetsAt: Date?

    public init(name: String, usedPercent: Int?, remainingPercent: Int?, resetsAt: Date?) {
        self.name = name
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }

    public static func unavailable(name: String) -> QuotaWindowSummary {
        QuotaWindowSummary(name: name, usedPercent: nil, remainingPercent: nil, resetsAt: nil)
    }
}

public struct AbarEventSummary: Identifiable, Equatable {
    public var id: String
    public var eventType: String
    public var toolName: String?
    public var status: String
    public var payloadJSON: String?
    public var createdAt: Date?

    public init(
        id: String,
        eventType: String,
        toolName: String?,
        status: String,
        payloadJSON: String? = nil,
        createdAt: Date?
    ) {
        self.id = id
        self.eventType = eventType
        self.toolName = toolName
        self.status = status
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}

public enum AbarTaskState: Equatable {
    case running
    case completed
}

public struct AbarTaskSummary: Identifiable, Equatable {
    public var id: String
    public var projectName: String
    public var promptPreview: String
    public var startedAt: Date
    public var lastActivityAt: Date
    public var durationSeconds: Int
    public var completedAt: Date?
    public var transcriptPath: String?
    public var sessionId: String
    public var turnId: String
    public var state: AbarTaskState

    public init(
        id: String,
        projectName: String,
        promptPreview: String,
        startedAt: Date,
        lastActivityAt: Date,
        durationSeconds: Int,
        completedAt: Date?,
        transcriptPath: String?,
        sessionId: String,
        turnId: String,
        state: AbarTaskState
    ) {
        self.id = id
        self.projectName = projectName
        self.promptPreview = promptPreview
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.durationSeconds = durationSeconds
        self.completedAt = completedAt
        self.transcriptPath = transcriptPath
        self.sessionId = sessionId
        self.turnId = turnId
        self.state = state
    }
}

public struct AbarTaskCompletionPulseDetector: Equatable {
    private var seenCompletedTaskIDs: Set<String> = []

    public init() {}

    public mutating func newCompletionIDs(in tasks: [AbarTaskSummary]) -> [String] {
        let completedIDs = Set(tasks.filter { $0.state == .completed }.map(\.id))
        let newIDs = completedIDs.subtracting(seenCompletedTaskIDs)
        seenCompletedTaskIDs.formUnion(completedIDs)
        return tasks
            .filter { newIDs.contains($0.id) }
            .map(\.id)
    }
}

public enum AbarStatusSignalResolver {
    public static let idleResetInterval: TimeInterval = 180

    public static func signal(
        tasks: [AbarTaskSummary],
        events: [AbarEventSummary],
        now: Date = Date(),
        acknowledgedAt: Date? = nil
    ) -> AbarStatusSignal {
        if let acknowledgedAt,
           let latestActivityAt = latestActivityAt(tasks: tasks, events: events),
           acknowledgedAt >= latestActivityAt {
            return .idle
        }

        if let interruptedAt = latestInterruptedAt(in: events),
           now.timeIntervalSince(interruptedAt) <= idleResetInterval,
           acknowledgedAt.map({ $0 < interruptedAt }) ?? true,
           latestRecoveryAt(tasks: tasks, events: events).map({ $0 < interruptedAt }) ?? true {
            return .interrupted
        }

        if tasks.contains(where: { $0.state == .running }) {
            return .running
        }

        return .idle
    }

    private static func latestActivityAt(tasks: [AbarTaskSummary], events: [AbarEventSummary]) -> Date? {
        let taskActivity = tasks.map(\.lastActivityAt)
        let eventActivity = events.compactMap(\.createdAt)
        return (taskActivity + eventActivity).max()
    }

    private static func latestInterruptedAt(in events: [AbarEventSummary]) -> Date? {
        events
            .filter(isInterrupted)
            .compactMap(\.createdAt)
            .max()
    }

    private static func latestRecoveryAt(tasks: [AbarTaskSummary], events: [AbarEventSummary]) -> Date? {
        let completedTaskActivity = tasks
            .filter { $0.state == .completed }
            .map(\.lastActivityAt)
        let successfulEventActivity = events
            .filter(isRecoveryEvent)
            .compactMap(\.createdAt)
        return (completedTaskActivity + successfulEventActivity).max()
    }

    private static func isRecoveryEvent(_ event: AbarEventSummary) -> Bool {
        event.status.lowercased() == "success" || event.eventType == "Stop"
    }

    private static func isInterrupted(_ event: AbarEventSummary) -> Bool {
        if event.status.lowercased() == "error" {
            return true
        }
        guard event.eventType != "UserPromptSubmit",
              let payload = payloadDictionary(event.payloadJSON)
        else {
            return false
        }
        return hasErrorField(payload)
            || hasErrorField(payload["tool_response"] as? [String: Any])
            || hasErrorField(payload["toolResponse"] as? [String: Any])
            || hasErrorField(payload["response"] as? [String: Any])
    }

    private static func hasErrorField(_ payload: [String: Any]?) -> Bool {
        guard let payload else { return false }
        if payload["error"] != nil {
            return true
        }
        if let status = payload["status"] as? String,
           status.lowercased() == "error" {
            return true
        }
        return ["error_message", "message", "reason", "stderr"].contains { key in
            guard let value = payload[key] as? String else { return false }
            let lowercased = value.lowercased()
            return ["hook exited", "cancel", "abort", "interrupt"].contains {
                lowercased.contains($0)
            }
        }
    }

    private static func payloadDictionary(_ json: String?) -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8)
        else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
