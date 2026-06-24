import AbarOverlayCore
import XCTest

final class AbarSamplingPolicyTests: XCTestCase {
    func testSnapshotSamplingUsesQuarterSecondInterval() {
        XCTAssertEqual(AbarSamplingPolicy.snapshotRefreshInterval, 0.25, accuracy: 0.001)
    }

    func testMaintenanceRefreshIntervalsStayCoarse() {
        XCTAssertEqual(AbarSamplingPolicy.quotaRefreshInterval, 30, accuracy: 0.001)
        XCTAssertEqual(AbarSamplingPolicy.skillScanInterval, 60, accuracy: 0.001)
    }
}
