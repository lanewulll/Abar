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
}
