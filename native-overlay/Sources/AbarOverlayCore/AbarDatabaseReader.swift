import Foundation
import SQLite3

public enum AbarDatabaseReaderError: Error, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
}

public final class AbarDatabaseReader {
    private static let runningTaskInactivityRetention: TimeInterval = 900

    private let databasePath: String
    private let codexHome: String
    private let now: () -> Date

    public init(
        databasePath: String,
        codexHome: String = AbarRuntimeConfiguration.codexHome(),
        now: @escaping () -> Date = Date.init
    ) {
        self.databasePath = databasePath
        self.codexHome = codexHome
        self.now = now
    }

    public func loadSnapshot() throws -> AbarSnapshot {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databasePath, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let db { sqlite3_close(db) }
            throw AbarDatabaseReaderError.openFailed(message)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2_000)

        let quota = try latestQuota(db: db)
        let events = try recentEvents(db: db, limit: 20)
        let tasks = try taskSummaries(db: db, limit: 1_000)
        let codexConnection = AbarCodexConnectionResolver.resolve(
            eventPayloads: events.compactMap(\.payloadJSON),
            codexHome: codexHome
        )
        return AbarSnapshot(
            fiveHour: quota.fiveHour,
            weekly: quota.weekly,
            skillsCount: try count(db: db, table: "skills"),
            eventsCount: try count(db: db, table: "events"),
            recentEvents: events,
            tasks: tasks,
            codexConnection: codexConnection,
            projectPath: try configValue(db: db, key: "project_path"),
            loadedAt: now()
        )
    }

    private func latestQuota(db: OpaquePointer) throws -> (fiveHour: QuotaWindowSummary, weekly: QuotaWindowSummary) {
        let successfulJSON = try firstText(
            db: db,
            sql: "SELECT snapshot_json FROM quota_snapshots WHERE error IS NULL OR error = '' ORDER BY created_at DESC LIMIT 1",
            bindings: []
        )
        let json: String?
        if let successfulJSON {
            json = successfulJSON
        } else {
            json = try firstText(
                db: db,
                sql: "SELECT snapshot_json FROM quota_snapshots ORDER BY created_at DESC LIMIT 1",
                bindings: []
            )
        }
        guard let json else {
            return (.unavailable(name: "5h"), .unavailable(name: "Weekly"))
        }

        guard
            let data = json.data(using: .utf8),
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let windows = root["windows"] as? [[String: Any]]
        else {
            return (.unavailable(name: "5h"), .unavailable(name: "Weekly"))
        }

        return (
            quotaWindow(named: "5h", in: windows, fallbackLabel: "5h"),
            quotaWindow(named: "weekly", in: windows, fallbackLabel: "Weekly")
        )
    }

    private func quotaWindow(
        named name: String,
        in windows: [[String: Any]],
        fallbackLabel: String
    ) -> QuotaWindowSummary {
        guard let window = windows.first(where: { ($0["name"] as? String) == name }) else {
            return .unavailable(name: fallbackLabel)
        }

        let label = (window["label"] as? String) ?? fallbackLabel
        let usedPercent = normalizedPercent(window["usedPercent"])
        let remainingPercent = normalizedPercent(window["remainingPercent"])
            ?? usedPercent.map { max(0, min(100, 100 - $0)) }
        let resetsAt = (window["resetsAt"] as? String).flatMap(Self.parseISODate)
        return QuotaWindowSummary(
            name: label,
            usedPercent: usedPercent,
            remainingPercent: remainingPercent,
            resetsAt: resetsAt
        )
    }

    private func normalizedPercent(_ value: Any?) -> Int? {
        let doubleValue: Double?
        if let number = value as? NSNumber {
            doubleValue = number.doubleValue
        } else if let number = value as? Double {
            doubleValue = number
        } else if let string = value as? String {
            doubleValue = Double(string)
        } else {
            doubleValue = nil
        }

        guard let doubleValue else { return nil }
        return Int(max(0, min(100, doubleValue)).rounded())
    }

    private func recentEvents(db: OpaquePointer, limit: Int) throws -> [AbarEventSummary] {
        var statement: OpaquePointer?
        let sql = """
            SELECT id, event_type, tool_name, status, payload_json, created_at
            FROM events
            ORDER BY created_at DESC
            LIMIT ?
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AbarDatabaseReaderError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var events: [AbarEventSummary] = []
        var stepStatus = sqlite3_step(statement)
        while stepStatus == SQLITE_ROW {
            events.append(
                AbarEventSummary(
                    id: columnText(statement, 0) ?? UUID().uuidString,
                    eventType: columnText(statement, 1) ?? "Unknown",
                    toolName: columnText(statement, 2),
                    status: columnText(statement, 3) ?? "unknown",
                    payloadJSON: columnText(statement, 4),
                    createdAt: columnText(statement, 5).flatMap(Self.parseISODate)
                )
            )
            stepStatus = sqlite3_step(statement)
        }

        guard stepStatus == SQLITE_DONE else {
            throw AbarDatabaseReaderError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
        return events
    }

    private func taskSummaries(db: OpaquePointer, limit: Int) throws -> [AbarTaskSummary] {
        let rows = try taskEventRows(db: db, limit: limit)
        let activityByTaskID = Dictionary(
            rows.compactMap { row -> (String, Date)? in
                guard let taskID = taskID(for: row) else { return nil }
                return (taskID, row.createdAt)
            },
            uniquingKeysWith: max
        )
        let prompts = rows.compactMap { row -> TaskPrompt? in
            guard row.eventType == "UserPromptSubmit" else { return nil }
            let payload = parsePayload(row.payloadJSON)
            let sessionId = payloadString(payload, "session_id") ?? row.sessionId ?? "unknown-session"
            let turnId = payloadString(payload, "turn_id") ?? row.id
            let projectPath = payloadString(payload, "cwd") ?? row.projectPath
            let rawPrompt = payloadString(payload, "prompt")
            let storedPreview = payloadString(payload, "prompt_preview")
            let prompt = rawPrompt ?? storedPreview ?? "Codex task"
            guard rawPrompt == nil || !Self.isInternalTaskPrompt(prompt) else { return nil }
            return TaskPrompt(
                id: "\(sessionId):\(turnId)",
                sessionId: sessionId,
                turnId: turnId,
                projectPath: projectPath,
                promptPreview: storedPreview ?? Self.promptPreview(prompt),
                transcriptPath: nil,
                startedAt: row.createdAt
            )
        }
        let stops = rows.compactMap { row -> TaskStop? in
            guard row.eventType == "Stop" else { return nil }
            let payload = parsePayload(row.payloadJSON)
            let sessionId = payloadString(payload, "session_id") ?? row.sessionId
            let turnId = payloadString(payload, "turn_id")
            guard let sessionId, let turnId else { return nil }
            return TaskStop(
                id: "\(sessionId):\(turnId)",
                sessionId: sessionId,
                completedAt: row.createdAt
            )
        }
        let stopByTaskID = Dictionary(stops.map { ($0.id, $0.completedAt) }, uniquingKeysWith: max)
        let newestPromptBySession = Dictionary(
            prompts.map { ($0.sessionId, $0) },
            uniquingKeysWith: { lhs, rhs in lhs.startedAt >= rhs.startedAt ? lhs : rhs }
        )
        let latestPromptAtByProject = prompts.reduce(into: [String: Date]()) { result, prompt in
            guard let projectPath = prompt.projectPath else { return }
            result[projectPath] = max(result[projectPath] ?? prompt.startedAt, prompt.startedAt)
        }
        let currentDate = now()
        let calendar = Calendar.current

        var tasks: [AbarTaskSummary] = []
        for prompt in prompts {
            let completedAt = stopByTaskID[prompt.id]
                ?? fallbackStopCompletedAt(for: prompt, prompts: prompts, stops: stops)
            if let completedAt {
                guard calendar.isDate(completedAt, inSameDayAs: currentDate) else {
                    continue
                }
            } else {
                guard calendar.isDate(prompt.startedAt, inSameDayAs: currentDate),
                      newestPromptBySession[prompt.sessionId]?.id == prompt.id
                else {
                    continue
                }
            }
            let lastActivityAt = completedAt ?? activityByTaskID[prompt.id] ?? prompt.startedAt
            let durationSeconds = max(0, Int(lastActivityAt.timeIntervalSince(prompt.startedAt)))
            if completedAt == nil,
               isStaleUnclosedPrompt(
                   prompt,
                   lastActivityAt: lastActivityAt,
                   latestPromptAtByProject: latestPromptAtByProject,
                   now: currentDate
               ) {
                continue
            }

            tasks.append(
                AbarTaskSummary(
                    id: prompt.id,
                    projectName: prompt.projectName,
                    promptPreview: prompt.promptPreview,
                    startedAt: prompt.startedAt,
                    lastActivityAt: lastActivityAt,
                    durationSeconds: durationSeconds,
                    completedAt: completedAt,
                    transcriptPath: prompt.transcriptPath,
                    sessionId: prompt.sessionId,
                    turnId: prompt.turnId,
                    state: completedAt == nil ? .running : .completed
                )
            )
        }

        let sortedTasks = tasks.sorted { lhs, rhs in
            if lhs.state != rhs.state {
                return lhs.state == .running
            }
            let lhsDate = sortDate(for: lhs)
            let rhsDate = sortDate(for: rhs)
            return lhsDate > rhsDate
        }
        return Array(sortedTasks.prefix(AbarTaskListSlots.visibleSlotCount))
    }

    private func isStaleUnclosedPrompt(
        _ prompt: TaskPrompt,
        lastActivityAt: Date,
        latestPromptAtByProject: [String: Date],
        now: Date
    ) -> Bool {
        guard let projectPath = prompt.projectPath,
              let latestProjectPromptAt = latestPromptAtByProject[projectPath],
              latestProjectPromptAt > prompt.startedAt
        else {
            return false
        }
        return now.timeIntervalSince(lastActivityAt) > Self.runningTaskInactivityRetention
    }

    private func fallbackStopCompletedAt(
        for prompt: TaskPrompt,
        prompts: [TaskPrompt],
        stops: [TaskStop]
    ) -> Date? {
        let nextPromptAt = prompts
            .filter { $0.sessionId == prompt.sessionId && $0.startedAt > prompt.startedAt }
            .map(\.startedAt)
            .min()

        return stops
            .filter { stop in
                stop.sessionId == prompt.sessionId
                    && stop.completedAt >= prompt.startedAt
                    && nextPromptAt.map { stop.completedAt < $0 } ?? true
            }
            .map(\.completedAt)
            .max()
    }

    private func sortDate(for task: AbarTaskSummary) -> Date {
        switch task.state {
        case .running:
            return task.lastActivityAt
        case .completed:
            return task.completedAt ?? task.lastActivityAt
        }
    }

    private func taskEventRows(db: OpaquePointer, limit: Int) throws -> [TaskEventRow] {
        var statement: OpaquePointer?
        let sql = """
            SELECT id, event_type, project_path, session_id, payload_json, created_at
            FROM events
            WHERE payload_json IS NOT NULL
            ORDER BY created_at DESC
            LIMIT ?
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AbarDatabaseReaderError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var rows: [TaskEventRow] = []
        var stepStatus = sqlite3_step(statement)
        while stepStatus == SQLITE_ROW {
            guard let id = columnText(statement, 0),
                  let eventType = columnText(statement, 1),
                  let createdAt = columnText(statement, 5).flatMap(Self.parseISODate)
            else {
                stepStatus = sqlite3_step(statement)
                continue
            }
            rows.append(
                TaskEventRow(
                    id: id,
                    eventType: eventType,
                    projectPath: columnText(statement, 2),
                    sessionId: columnText(statement, 3),
                    payloadJSON: columnText(statement, 4),
                    createdAt: createdAt
                )
            )
            stepStatus = sqlite3_step(statement)
        }

        guard stepStatus == SQLITE_DONE else {
            throw AbarDatabaseReaderError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
        return rows
    }

    private func count(db: OpaquePointer, table: String) throws -> Int {
        let allowedTables = ["skills", "events"]
        precondition(allowedTables.contains(table))
        let sql = "SELECT COUNT(*) FROM \(table)"
        return Int(try firstInt(db: db, sql: sql, bindings: []) ?? 0)
    }

    private func configValue(db: OpaquePointer, key: String) throws -> String? {
        try firstText(db: db, sql: "SELECT value FROM app_config WHERE key = ? LIMIT 1", bindings: [key])
    }

    private func firstText(db: OpaquePointer, sql: String, bindings: [String]) throws -> String? {
        try querySingle(db: db, sql: sql, bindings: bindings) { statement in
            columnText(statement, 0)
        }
    }

    private func firstInt(db: OpaquePointer, sql: String, bindings: [String]) throws -> Int64? {
        try querySingle(db: db, sql: sql, bindings: bindings) { statement in
            sqlite3_column_type(statement, 0) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 0)
        }
    }

    private func querySingle<T>(
        db: OpaquePointer,
        sql: String,
        bindings: [String],
        map: (OpaquePointer) -> T?
    ) throws -> T? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AbarDatabaseReaderError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }

        let stepStatus = sqlite3_step(statement)
        if stepStatus == SQLITE_ROW {
            return map(statement)
        }
        guard stepStatus == SQLITE_DONE else {
            throw AbarDatabaseReaderError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
        return nil
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: pointer)
    }

    private func parsePayload(_ json: String?) -> [String: Any] {
        guard let json,
              let data = json.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return payload
    }

    private func payloadString(_ payload: [String: Any], _ key: String) -> String? {
        if let string = payload[key] as? String, !string.isEmpty {
            return string
        }
        return nil
    }

    private func taskID(for row: TaskEventRow) -> String? {
        let payload = parsePayload(row.payloadJSON)
        let sessionId = payloadString(payload, "session_id") ?? row.sessionId
        let turnId = payloadString(payload, "turn_id")
        guard let sessionId, let turnId else { return nil }
        return "\(sessionId):\(turnId)"
    }

    private static func promptPreview(_ prompt: String) -> String {
        let compact = displayPromptText(from: prompt).filter { !$0.isWhitespace && !$0.isNewline }
        guard compact.count > 15 else {
            return compact.isEmpty ? "Codex" : String(compact)
        }
        return String(compact.prefix(15)) + "..."
    }

    private static func displayPromptText(from prompt: String) -> String {
        let marker = "## My request for Codex:"
        let displayPrompt: String
        if let range = prompt.range(of: marker) {
            displayPrompt = String(prompt[range.upperBound...])
        } else {
            displayPrompt = prompt
        }
        return planPromptTitle(from: displayPrompt) ?? displayPrompt
    }

    private static func planPromptTitle(from prompt: String) -> String? {
        let marker = "PLEASE IMPLEMENT THIS PLAN:"
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix(marker) else {
            return nil
        }

        let planBody = normalized.dropFirst(marker.count)
        for line in planBody.split(whereSeparator: \.isNewline) {
            let heading = line.trimmingCharacters(in: .whitespaces)
            guard heading.hasPrefix("#"), !heading.hasPrefix("##") else {
                continue
            }
            let title = heading.dropFirst()
            guard title.first?.isWhitespace == true else {
                continue
            }
            let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
            if !trimmedTitle.isEmpty {
                return trimmedTitle
            }
        }
        return "执行计划模式计划"
    }

    private static func isInternalTaskPrompt(_ prompt: String) -> Bool {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return isInternalSuggestionPrompt(normalized) || isAmbientSafetyPrompt(normalized)
    }

    private static func isInternalSuggestionPrompt(_ normalized: String) -> Bool {
        return normalized.hasPrefix("# Overview")
            && normalized.contains("Generate 0 to 3 hyperpersonalized suggestions")
            && normalized.contains("what this user can do with Codex")
    }

    private static func isAmbientSafetyPrompt(_ normalized: String) -> Bool {
        normalized.hasPrefix("You are an expert at upholding safety and compliance standards for Codex ambient suggestions")
            && normalized.contains("ambient suggestion candidates")
    }

    private static func parseISODate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct TaskEventRow {
    var id: String
    var eventType: String
    var projectPath: String?
    var sessionId: String?
    var payloadJSON: String?
    var createdAt: Date
}

private struct TaskPrompt {
    var id: String
    var sessionId: String
    var turnId: String
    var projectPath: String?
    var promptPreview: String
    var transcriptPath: String?
    var startedAt: Date

    var projectName: String {
        guard let projectPath else { return "Codex" }
        let name = URL(fileURLWithPath: projectPath).lastPathComponent
        return name.isEmpty ? "Codex" : name
    }
}

private struct TaskStop {
    var id: String
    var sessionId: String
    var completedAt: Date
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
