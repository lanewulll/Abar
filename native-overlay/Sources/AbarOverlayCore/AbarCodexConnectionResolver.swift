import Foundation

public enum AbarCodexConnectionMode: Equatable, Sendable {
    case account
    case api
    case unknown
}

public struct AbarCodexConnectionSummary: Equatable, Sendable {
    public var mode: AbarCodexConnectionMode
    public var displayText: String

    public init(mode: AbarCodexConnectionMode, displayText: String) {
        self.mode = mode
        self.displayText = displayText
    }

    public static let unknown = AbarCodexConnectionSummary(mode: .unknown, displayText: "未检测到 Codex")
}

public enum AbarCodexConnectionResolver {
    public static let defaultBaseURL = "https://api.openai.com/v1"

    public static func resolve(eventPayloads: [String], codexHome: String) -> AbarCodexConnectionSummary {
        let authPath = (codexHome as NSString).appendingPathComponent("auth.json")
        let authJSON = try? String(contentsOfFile: authPath, encoding: .utf8)
        return resolve(eventPayloads: eventPayloads, authJSON: authJSON)
    }

    public static func resolve(eventPayloads: [String], authJSON: String?) -> AbarCodexConnectionSummary {
        for payloadJSON in eventPayloads {
            guard let connection = abarConnection(from: payloadJSON),
                  let mode = string(connection["mode"])
            else {
                continue
            }

            if mode == "api" {
                return AbarCodexConnectionSummary(
                    mode: .api,
                    displayText: string(connection["baseUrl"] ?? connection["baseURL"] ?? connection["base_url"]) ?? defaultBaseURL
                )
            }
            if mode == "account" {
                return accountSummary()
            }
        }

        if authJSON != nil {
            return accountSummary()
        }
        return .unknown
    }

    private static func accountSummary() -> AbarCodexConnectionSummary {
        AbarCodexConnectionSummary(
            mode: .account,
            displayText: "Codex 账户"
        )
    }

    private static func abarConnection(from json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return payload["abar_connection"] as? [String: Any]
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
