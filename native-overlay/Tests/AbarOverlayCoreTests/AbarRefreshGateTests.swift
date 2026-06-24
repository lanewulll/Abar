import AbarOverlayCore
import XCTest

final class AbarRefreshGateTests: XCTestCase {
    func testPreventsConcurrentRefreshesUntilFinished() {
        var gate = AbarRefreshGate()

        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.begin())

        gate.finish()

        XCTAssertTrue(gate.begin())
    }
}
