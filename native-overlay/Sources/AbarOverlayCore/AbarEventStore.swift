import Foundation
import SQLite3

public enum AbarEventStoreError: Error, Equatable {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
}

public struct AbarStoredEvent: Equatable {
    public var id: String
    public var agent: String
    public var eventType: String
    public var projectPath: String?
    public var sessionId: String?
    public var toolName: String?
    public var toolUseId: String?
    public var status: String
    public var payloadJSON: String
    public var createdAt: String

    public init(
        id: String,
        agent: String = "codex",
        eventType: String,
        projectPath: String?,
        sessionId: String?,
        toolName: String?,
        toolUseId: String?,
        status: String,
        payloadJSON: String,
        createdAt: String
    ) {
        self.id = id
        self.agent = agent
        self.eventType = eventType
        self.projectPath = projectPath
        self.sessionId = sessionId
        self.toolName = toolName
        self.toolUseId = toolUseId
        self.status = status
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}

public struct AbarStoredSkill: Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var path: String
    public var source: String
    public var skillMDPath: String
    public var hasSkillMD: Bool
    public var lastModifiedAt: String?

    public init(
        id: String,
        name: String,
        description: String,
        path: String,
        source: String,
        skillMDPath: String,
        hasSkillMD: Bool = true,
        lastModifiedAt: String?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.path = path
        self.source = source
        self.skillMDPath = skillMDPath
        self.hasSkillMD = hasSkillMD
        self.lastModifiedAt = lastModifiedAt
    }
}

public struct AbarStoredQuotaSnapshot: Equatable {
    public var provider: String
    public var source: String
    public var confidence: String
    public var snapshotJSON: String
    public var error: String?

    public init(
        provider: String = "codex",
        source: String,
        confidence: String,
        snapshotJSON: String,
        error: String?
    ) {
        self.provider = provider
        self.source = source
        self.confidence = confidence
        self.snapshotJSON = snapshotJSON
        self.error = error
    }
}

public final class AbarEventStore: @unchecked Sendable {
    private let databasePath: String

    public init(databasePath: String) {
        self.databasePath = databasePath
    }

    public func initialize(defaultPort: Int = 3987) throws {
        try FileManager.default.createDirectory(
            atPath: (databasePath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try withDatabase { db in
            try exec(db, schemaSQL)
            try setConfig(db, key: "local_server_port", value: String(defaultPort))
        }
    }

    public func insertEvent(_ event: AbarStoredEvent) throws {
        try withDatabase { db in
            let sql = """
                INSERT INTO events (
                  id, agent, event_type, project_path, session_id, tool_name,
                  tool_use_id, status, payload_json, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw AbarEventStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            bind(statement, 1, event.id)
            bind(statement, 2, event.agent)
            bind(statement, 3, event.eventType)
            bind(statement, 4, event.projectPath)
            bind(statement, 5, event.sessionId)
            bind(statement, 6, event.toolName)
            bind(statement, 7, event.toolUseId)
            bind(statement, 8, event.status)
            bind(statement, 9, event.payloadJSON)
            bind(statement, 10, event.createdAt)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AbarEventStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func replaceSkills(_ skills: [AbarStoredSkill], scannedAt: String = ISO8601DateFormatter().string(from: Date())) throws {
        try withDatabase { db in
            try exec(db, "BEGIN IMMEDIATE TRANSACTION")
            do {
                try exec(db, "DELETE FROM skills")
                let sql = """
                    INSERT INTO skills (
                      id, project_id, name, description, path, source, skill_md_path,
                      has_skill_md, last_modified_at, scanned_at
                    ) VALUES (?, NULL, ?, ?, ?, ?, ?, ?, ?, ?)
                    """
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                    throw AbarEventStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
                }
                defer { sqlite3_finalize(statement) }

                for skill in skills {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(statement, 1, skill.id)
                    bind(statement, 2, skill.name)
                    bind(statement, 3, skill.description)
                    bind(statement, 4, skill.path)
                    bind(statement, 5, skill.source)
                    bind(statement, 6, skill.skillMDPath)
                    sqlite3_bind_int(statement, 7, skill.hasSkillMD ? 1 : 0)
                    bind(statement, 8, skill.lastModifiedAt)
                    bind(statement, 9, scannedAt)
                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw AbarEventStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
                    }
                }
                try exec(db, "COMMIT")
            } catch {
                try? exec(db, "ROLLBACK")
                throw error
            }
        }
    }

    public func insertQuotaSnapshot(_ snapshot: AbarStoredQuotaSnapshot) throws {
        try withDatabase { db in
            let sql = """
                INSERT INTO quota_snapshots (provider, source, confidence, snapshot_json, error, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw AbarEventStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            bind(statement, 1, snapshot.provider)
            bind(statement, 2, snapshot.source)
            bind(statement, 3, snapshot.confidence)
            bind(statement, 4, snapshot.snapshotJSON)
            bind(statement, 5, snapshot.error)
            bind(statement, 6, ISO8601DateFormatter().string(from: Date()))

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AbarEventStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func configValue(key: String) throws -> String? {
        try withDatabase { db in
            let sql = "SELECT value FROM app_config WHERE key = ? LIMIT 1"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw AbarEventStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            bind(statement, 1, key)
            let status = sqlite3_step(statement)
            if status == SQLITE_ROW {
                guard let pointer = sqlite3_column_text(statement, 0) else {
                    return nil
                }
                return String(cString: pointer)
            }
            guard status == SQLITE_DONE else {
                throw AbarEventStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
            return nil
        }
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let db { sqlite3_close(db) }
            throw AbarEventStoreError.openFailed(message)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2_000)
        try exec(db, "PRAGMA journal_mode = WAL")
        return try body(db)
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(error)
            throw AbarEventStoreError.execFailed(message)
        }
    }

    private func setConfig(_ db: OpaquePointer, key: String, value: String) throws {
        let sql = """
            INSERT INTO app_config (key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AbarEventStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, key)
        bind(statement, 2, value)
        bind(statement, 3, ISO8601DateFormatter().string(from: Date()))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AbarEventStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
}

private let schemaSQL = """
CREATE TABLE IF NOT EXISTS app_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  path TEXT NOT NULL UNIQUE,
  is_active INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS skills (
  id TEXT PRIMARY KEY,
  project_id TEXT,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  path TEXT NOT NULL,
  source TEXT NOT NULL,
  skill_md_path TEXT NOT NULL,
  has_skill_md INTEGER NOT NULL,
  last_modified_at TEXT,
  scanned_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY,
  agent TEXT NOT NULL,
  event_type TEXT NOT NULL,
  project_path TEXT,
  session_id TEXT,
  tool_name TEXT,
  tool_use_id TEXT,
  status TEXT,
  payload_json TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_created_at ON events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_tool_name ON events(tool_name);

CREATE TABLE IF NOT EXISTS quota_snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  provider TEXT NOT NULL,
  source TEXT NOT NULL,
  confidence TEXT NOT NULL,
  snapshot_json TEXT NOT NULL,
  error TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_quota_snapshots_created_at ON quota_snapshots(created_at DESC);
"""

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
