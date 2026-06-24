import AbarOverlayCore
import XCTest

final class AbarOverlayPresentationPolicyTests: XCTestCase {
    func testPanelUsesNoAppKitShadow() {
        XCTAssertFalse(AbarOverlayPresentationPolicy.hasAppKitShadow)
    }

    func testFrameAnimationUsesShortEaseDuration() {
        XCTAssertEqual(AbarOverlayPresentationPolicy.frameAnimationDuration, 0.20, accuracy: 0.001)
    }
}
