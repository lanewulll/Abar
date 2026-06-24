import AbarOverlayCore
import XCTest

final class AbarCodexConnectionResolverTests: XCTestCase {
    func testApiConnectionUsesBaseURLFromLatestHookPayload() {
        let summary = AbarCodexConnectionResolver.resolve(
            eventPayloads: [
                #"{"abar_connection":{"mode":"api","baseUrl":"https://gateway.example.com/v1","hasApiKey":true}}"#
            ],
            authJSON: nil
        )

        XCTAssertEqual(summary.mode, .api)
        XCTAssertEqual(summary.displayText, "https://gateway.example.com/v1")
    }

    func testApiConnectionFallsBackToDefaultBaseURLWhenMissing() {
        let summary = AbarCodexConnectionResolver.resolve(
            eventPayloads: [
                #"{"abar_connection":{"mode":"api","hasApiKey":true}}"#
            ],
            authJSON: nil
        )

        XCTAssertEqual(summary.mode, .api)
        XCTAssertEqual(summary.displayText, AbarCodexConnectionResolver.defaultBaseURL)
    }

    func testAccountConnectionUsesEmailFromAuthJWT() {
        let token = Self.jwt(payload: #"{"email":"user@example.com","sub":"user-1"}"#)
        let authJSON = #"{"auth_mode":"chatgpt","tokens":{"id_token":"\#(token)"}}"#

        let summary = AbarCodexConnectionResolver.resolve(
            eventPayloads: [
                #"{"abar_connection":{"mode":"account","hasApiKey":false}}"#
            ],
            authJSON: authJSON
        )

        XCTAssertEqual(summary.mode, .account)
        XCTAssertEqual(summary.displayText, "user@example.com")
        XCTAssertFalse(summary.displayText.contains(token))
    }

    func testAccountConnectionFallsBackWhenEmailIsMissing() {
        let summary = AbarCodexConnectionResolver.resolve(
            eventPayloads: [
                #"{"abar_connection":{"mode":"account","hasApiKey":false}}"#
            ],
            authJSON: #"{"auth_mode":"chatgpt","tokens":{}}"#
        )

        XCTAssertEqual(summary.mode, .account)
        XCTAssertEqual(summary.displayText, "Codex account")
    }

    private static func jwt(payload: String) -> String {
        [
            base64URL(#"{"alg":"none"}"#),
            base64URL(payload),
            "signature"
        ].joined(separator: ".")
    }

    private static func base64URL(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
