import Foundation

public enum AbarQuotaRefresher {
    public static let whamUsageURL = "https://chatgpt.com/backend-api/wham/usage"

    public static func refresh(
        codexHome: String = (NSHomeDirectory() as NSString).appendingPathComponent(".codex"),
        timeoutSeconds: Int = 15
    ) -> AbarStoredQuotaSnapshot {
        let auth = readAuth(codexHome: codexHome)
        guard let accessToken = auth.accessToken else {
            return errorSnapshot(
                source: "codex_auth_state",
                error: auth.error ?? "Codex auth.json does not contain an access token."
            )
        }

        do {
            let response = try requestWhamUsage(accessToken: accessToken, accountID: auth.accountID, timeoutSeconds: timeoutSeconds)
            guard (200..<300).contains(response.status) else {
                return errorSnapshot(
                    source: "internal_web_api",
                    error: "wham/usage returned HTTP \(response.status)."
                )
            }
            let raw = try JSONSerialization.jsonObject(with: Data(response.body.utf8))
            return normalizedSnapshot(raw: raw)
        } catch {
            return errorSnapshot(source: "internal_web_api", error: String(describing: error))
        }
    }

    private static func normalizedSnapshot(raw: Any) -> AbarStoredQuotaSnapshot {
        let root = raw as? [String: Any] ?? [:]
        let rateLimit = root["rate_limit"] as? [String: Any] ?? [:]
        var windows: [[String: Any]] = []
        if let primary = normalizedWindow(rateLimit["primary_window"]) {
            windows.append(primary)
        }
        if let secondary = normalizedWindow(rateLimit["secondary_window"]) {
            windows.append(secondary)
        }

        var snapshot: [String: Any] = [
            "provider": "codex",
            "source": "internal_web_api",
            "confidence": windows.isEmpty ? "low" : "high",
            "windows": windows,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "raw": sanitize(raw)
        ]
        if windows.isEmpty {
            snapshot["error"] = "No usable Codex quota windows found in internal web API response."
        }

        let json = jsonString(snapshot)
        return AbarStoredQuotaSnapshot(
            source: "internal_web_api",
            confidence: windows.isEmpty ? "low" : "high",
            snapshotJSON: json,
            error: snapshot["error"] as? String
        )
    }

    private static func normalizedWindow(_ raw: Any?) -> [String: Any]? {
        guard let record = raw as? [String: Any] else {
            return nil
        }
        let usedPercent = number(record["used_percent"] ?? record["usedPercent"] ?? record["utilization"])
        let remainingPercent = number(record["remaining_percent"] ?? record["remainingPercent"])
            ?? usedPercent.map { clamp(100 - $0) }
        let windowSeconds = number(record["limit_window_seconds"] ?? record["limitWindowSeconds"])
        let resetAt = normalizedResetAt(record["reset_at"] ?? record["resetAt"])
        let resetInSeconds = number(
            record["reset_after_seconds"] ??
                record["resetAfterSeconds"] ??
                record["reset_in_seconds"] ??
                record["resetInSeconds"]
        ) ?? secondsUntil(resetAt)

        if usedPercent == nil, remainingPercent == nil, resetAt == nil, resetInSeconds == nil {
            return nil
        }

        var window: [String: Any] = [
            "name": windowName(seconds: windowSeconds),
            "unit": "unknown"
        ]
        if let usedPercent {
            window["usedPercent"] = clamp(usedPercent)
        }
        if let remainingPercent {
            window["remainingPercent"] = clamp(remainingPercent)
        }
        if let resetAt {
            window["resetsAt"] = resetAt
        }
        if let resetInSeconds {
            window["resetInSeconds"] = max(0, Int(resetInSeconds.rounded()))
        }
        return window
    }

    private static func readAuth(codexHome: String) -> (accessToken: String?, accountID: String?, error: String?) {
        let path = (codexHome as NSString).appendingPathComponent("auth.json")
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let tokens = json?["tokens"] as? [String: Any] ?? [:]
            let accessToken = string(tokens["access_token"] ?? tokens["accessToken"])
            let idToken = string(tokens["id_token"] ?? tokens["idToken"])
            let explicitAccount = string(tokens["account_id"] ?? tokens["accountId"])
            let jwtAccount = accountIDFromJWT(accessToken) ?? accountIDFromJWT(idToken)
            return (accessToken, explicitAccount ?? jwtAccount, accessToken == nil ? "Codex auth.json exists but does not contain tokens.access_token." : nil)
        } catch {
            return (nil, nil, "Unable to read Codex auth.json: \(error)")
        }
    }

    private static func requestWhamUsage(accessToken: String, accountID: String?, timeoutSeconds: Int) throws -> (status: Int, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "--silent",
            "--show-error",
            "--location",
            "--max-time",
            String(max(1, timeoutSeconds)),
            "--write-out",
            "\n__ABAR_HTTP_STATUS__:%{http_code}",
            "--config",
            "-"
        ]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        stdin.fileHandleForWriting.write(Data(curlConfig(accessToken: accessToken, accountID: accountID).utf8))
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "AbarQuotaRefresher", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: error.isEmpty ? "curl exited with \(process.terminationStatus)" : error
            ])
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let marker = "\n__ABAR_HTTP_STATUS__:"
        guard let range = output.range(of: marker, options: .backwards),
              let status = Int(output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw NSError(domain: "AbarQuotaRefresher", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "wham/usage response did not include an HTTP status marker."
            ])
        }
        return (status, String(output[..<range.lowerBound]))
    }

    private static func curlConfig(accessToken: String, accountID: String?) -> String {
        var headers = [
            "Authorization: Bearer \(accessToken)",
            "Accept: application/json",
            "User-Agent: Abar/0.1 CodexQuotaProvider"
        ]
        if let accountID {
            headers.append("ChatGPT-Account-ID: \(accountID)")
        }
        return ([
            #"url = "\#(whamUsageURL)""#,
            #"request = "GET""#
        ] + headers.map { #"header = "\#(escapeCurlValue($0))""# }).joined(separator: "\n")
    }

    private static func accountIDFromJWT(_ token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        if let claim = json["https://api.openai.com/auth"] as? [String: Any] {
            return string(claim["chatgpt_account_id"])
        }
        return string(json["chatgpt_account_id"])
    }

    private static func errorSnapshot(source: String, error: String) -> AbarStoredQuotaSnapshot {
        let snapshot: [String: Any] = [
            "provider": "codex",
            "source": source,
            "confidence": "low",
            "windows": [],
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "error": error
        ]
        return AbarStoredQuotaSnapshot(source: source, confidence: "low", snapshotJSON: jsonString(snapshot), error: error)
    }

    private static func normalizedResetAt(_ value: Any?) -> String? {
        if let number = number(value) {
            let seconds = number > 1_000_000_000_000 ? number / 1_000 : number
            return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: seconds))
        }
        if let text = string(value) {
            if let numeric = Double(text) {
                return normalizedResetAt(numeric)
            }
            return ISO8601DateFormatter().date(from: text).map { ISO8601DateFormatter().string(from: $0) } ?? text
        }
        return nil
    }

    private static func secondsUntil(_ isoDate: String?) -> Double? {
        guard let isoDate, let date = ISO8601DateFormatter().date(from: isoDate) else {
            return nil
        }
        return max(0, date.timeIntervalSinceNow)
    }

    private static func windowName(seconds: Double?) -> String {
        guard let seconds = seconds.map({ Int($0.rounded()) }) else {
            return "unknown"
        }
        if seconds == 18_000 { return "5h" }
        if seconds == 604_800 { return "weekly" }
        return "unknown"
    }

    private static func sanitize(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var sanitized: [String: Any] = [:]
            for (key, item) in dictionary {
                sanitized[key] = key.lowercased().contains("token") ? "[redacted]" : sanitize(item)
            }
            return sanitized
        }
        if let array = value as? [Any] {
            return array.map(sanitize)
        }
        return value
    }

    private static func jsonString(_ value: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func clamp(_ value: Double) -> Double {
        min(100, max(0, (value * 10).rounded() / 10))
    }

    private static func escapeCurlValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
