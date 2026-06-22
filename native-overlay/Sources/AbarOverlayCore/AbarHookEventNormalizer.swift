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
        let payloadJSON = try sanitizedJSONString(from: object)
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

    private static func sanitizedJSONString(from value: Any) throws -> String {
        let sanitized = sanitize(value)
        guard JSONSerialization.isValidJSONObject(sanitized) else {
            throw AbarHookEventNormalizerError.invalidJSON
        }
        let data = try JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func sanitize(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var sanitized: [String: Any] = [:]
            for (key, item) in dictionary {
                sanitized[key] = isSensitiveKey(key) ? "[redacted]" : sanitize(item)
            }
            return sanitized
        }
        if let array = value as? [Any] {
            return array.map(sanitize)
        }
        return value
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return ["authorization", "password", "secret", "token", "api_key", "apikey"].contains {
            lower.contains($0)
        }
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
