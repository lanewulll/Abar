import Foundation

public enum AbarHookEventNormalizerError: Error, Equatable {
    case invalidJSON
    case invalidPayload
}

public enum AbarHookEventNormalizer {
    public static func normalize(data: Data, now: Date = Date()) throws -> AbarStoredEvent {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let record = object as? [String: Any] else {
            throw AbarHookEventNormalizerError.invalidPayload
        }

        let eventName = string(record["hook_event_name"] ?? record["eventType"] ?? record["event_type"])
        let eventType = normalizeEventType(eventName)
        let payloadJSON = try minimalPayloadJSONString(from: record)
        return AbarStoredEvent(
            id: string(record["id"]) ?? UUID().uuidString,
            eventType: eventType,
            projectPath: string(record["cwd"] ?? record["projectPath"] ?? record["project_path"]),
            sessionId: string(record["session_id"] ?? record["sessionId"]),
            toolName: string(record["tool_name"] ?? record["toolName"] ?? record["agent_type"]),
            toolUseId: string(record["tool_use_id"] ?? record["toolUseId"]),
            status: normalizeStatus(record: record, eventType: eventType),
            payloadJSON: payloadJSON,
            createdAt: normalizeCreatedAt(record["createdAt"] ?? record["created_at"], fallback: now)
        )
    }

    private static func normalizeEventType(_ value: String?) -> String {
        let known = [
            "SessionStart",
            "SessionEnd",
            "PreToolUse",
            "PostToolUse",
            "UserPromptSubmit",
            "Stop",
            "SubagentStart",
            "SubagentStop"
        ]
        guard let value, known.contains(value) else {
            return "Unknown"
        }
        return value
    }

    private static func normalizeStatus(record: [String: Any], eventType: String) -> String {
        if let explicit = string(record["status"]), ["success", "error", "unknown"].contains(explicit) {
            return explicit
        }
        let response = record["tool_response"] ?? record["toolResponse"] ?? record["response"]
        if dictionary(response)?["error"] != nil || record["error"] != nil {
            return "error"
        }
        return eventType == "PostToolUse" ? "success" : "unknown"
    }

    private static func normalizeCreatedAt(_ value: Any?, fallback: Date) -> String {
        if let value = value as? String {
            if let date = ISO8601DateFormatter().date(from: value) {
                return ISO8601DateFormatter().string(from: date)
            }
        } else if let value = value as? NSNumber {
            return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: value.doubleValue / 1_000))
        }
        return ISO8601DateFormatter().string(from: fallback)
    }

    static func minimalPayloadJSONString(from record: [String: Any]) throws -> String {
        var minimal: [String: Any] = [:]
        copyString(record, keys: ["hook_event_name", "eventType", "event_type"], to: "hook_event_name", in: &minimal)
        copyString(record, keys: ["cwd", "projectPath", "project_path"], to: "cwd", in: &minimal)
        copyString(record, keys: ["session_id", "sessionId"], to: "session_id", in: &minimal)
        copyString(record, keys: ["turn_id", "turnId"], to: "turn_id", in: &minimal)
        copyString(record, keys: ["tool_name", "toolName", "agent_type"], to: "tool_name", in: &minimal)
        copyString(record, keys: ["status"], to: "status", in: &minimal)
        if let prompt = string(record["prompt"]) {
            minimal["prompt_preview"] = promptPreview(prompt)
        } else if let preview = string(record["prompt_preview"]) {
            minimal["prompt_preview"] = promptPreview(preview)
        }
        if let connection = record["abar_connection"] as? [String: Any],
           let mode = string(connection["mode"]) {
            var savedConnection: [String: Any] = ["mode": mode]
            if mode == "api", let baseURL = string(connection["baseUrl"] ?? connection["baseURL"] ?? connection["base_url"]) {
                savedConnection["baseUrl"] = baseURL
            }
            minimal["abar_connection"] = savedConnection
        }

        guard JSONSerialization.isValidJSONObject(minimal) else {
            throw AbarHookEventNormalizerError.invalidJSON
        }
        let data = try JSONSerialization.data(withJSONObject: minimal, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func copyString(
        _ record: [String: Any],
        keys: [String],
        to destination: String,
        in minimal: inout [String: Any]
    ) {
        for key in keys {
            if let value = string(record[key]) {
                minimal[destination] = value
                return
            }
        }
    }

    private static func promptPreview(_ prompt: String) -> String {
        let compact = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard compact.count > 15 else {
            return compact
        }
        return String(compact.prefix(15)) + "..."
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
