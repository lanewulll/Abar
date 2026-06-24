import Foundation

public enum AbarRuntimeConfiguration {
    public static let defaultServerPort: UInt16 = 3987

    public static func serverPort(environment: [String: String] = ProcessInfo.processInfo.environment) -> UInt16 {
        guard
            let rawValue = environment["ABAR_SERVER_PORT"],
            let port = UInt16(rawValue),
            port > 0
        else {
            return defaultServerPort
        }
        return port
    }

    public static func codexHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> String {
        if let override = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        return (home as NSString).appendingPathComponent(".codex")
    }

    public static func nodeExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) + "/node" }
        let candidates = pathCandidates + [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node"
        ]
        return candidates.first(where: isExecutable)
    }
}
