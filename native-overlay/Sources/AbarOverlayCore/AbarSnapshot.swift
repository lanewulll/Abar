import Foundation

public struct AbarSnapshot: Equatable {
    public var fiveHour: QuotaWindowSummary
    public var weekly: QuotaWindowSummary
    public var skillsCount: Int
    public var eventsCount: Int
    public var recentEvents: [AbarEventSummary]
    public var tasks: [AbarTaskSummary]
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
        projectPath: String?,
        loadedAt: Date
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.skillsCount = skillsCount
        self.eventsCount = eventsCount
        self.recentEvents = recentEvents
        self.tasks = tasks
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
            projectPath: nil,
            loadedAt: now
        )
    }
}

public enum AbarActivityState: Equatable {
    case idle
    case working
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
    public var createdAt: Date?

    public init(id: String, eventType: String, toolName: String?, status: String, createdAt: Date?) {
        self.id = id
        self.eventType = eventType
        self.toolName = toolName
        self.status = status
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
