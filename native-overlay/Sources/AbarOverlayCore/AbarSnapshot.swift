import Foundation

public struct AbarSnapshot: Equatable {
    public var fiveHour: QuotaWindowSummary
    public var weekly: QuotaWindowSummary
    public var skillsCount: Int
    public var eventsCount: Int
    public var recentEvents: [AbarEventSummary]
    public var projectPath: String?
    public var loadedAt: Date

    public init(
        fiveHour: QuotaWindowSummary,
        weekly: QuotaWindowSummary,
        skillsCount: Int,
        eventsCount: Int,
        recentEvents: [AbarEventSummary],
        projectPath: String?,
        loadedAt: Date
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.skillsCount = skillsCount
        self.eventsCount = eventsCount
        self.recentEvents = recentEvents
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
            projectPath: nil,
            loadedAt: now
        )
    }
}

public struct QuotaWindowSummary: Equatable {
    public var name: String
    public var usedPercent: Int?
    public var resetsAt: Date?

    public init(name: String, usedPercent: Int?, resetsAt: Date?) {
        self.name = name
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    public static func unavailable(name: String) -> QuotaWindowSummary {
        QuotaWindowSummary(name: name, usedPercent: nil, resetsAt: nil)
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
