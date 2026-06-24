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
}
