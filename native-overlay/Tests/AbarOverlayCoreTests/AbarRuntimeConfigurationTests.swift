import AbarOverlayCore
import XCTest

final class AbarRuntimeConfigurationTests: XCTestCase {
    func testServerPortUsesDefaultWhenEnvironmentValueIsMissingOrInvalid() {
        XCTAssertEqual(AbarRuntimeConfiguration.serverPort(environment: [:]), 3987)
        XCTAssertEqual(AbarRuntimeConfiguration.serverPort(environment: ["ABAR_SERVER_PORT": "invalid"]), 3987)
        XCTAssertEqual(AbarRuntimeConfiguration.serverPort(environment: ["ABAR_SERVER_PORT": "0"]), 3987)
        XCTAssertEqual(AbarRuntimeConfiguration.serverPort(environment: ["ABAR_SERVER_PORT": "70000"]), 3987)
    }

    func testServerPortUsesValidEnvironmentValue() {
        XCTAssertEqual(AbarRuntimeConfiguration.serverPort(environment: ["ABAR_SERVER_PORT": "4567"]), 4567)
    }

    func testCodexHomeUsesEnvironmentOverride() {
        XCTAssertEqual(
            AbarRuntimeConfiguration.codexHome(environment: ["CODEX_HOME": "/tmp/codex"], home: "/Users/demo"),
            "/tmp/codex"
        )
        XCTAssertEqual(
            AbarRuntimeConfiguration.codexHome(environment: [:], home: "/Users/demo"),
            "/Users/demo/.codex"
        )
    }

    func testNodeExecutableFindsPathAndHomebrewFallbacks() {
        let executable = AbarRuntimeConfiguration.nodeExecutable(
            environment: ["PATH": "/custom/bin:/usr/bin"],
            isExecutable: { $0 == "/custom/bin/node" }
        )
        XCTAssertEqual(executable, "/custom/bin/node")

        let homebrew = AbarRuntimeConfiguration.nodeExecutable(
            environment: ["PATH": "/usr/bin"],
            isExecutable: { $0 == "/opt/homebrew/bin/node" }
        )
        XCTAssertEqual(homebrew, "/opt/homebrew/bin/node")
    }
}
