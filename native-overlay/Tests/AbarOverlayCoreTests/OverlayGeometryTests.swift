import AbarOverlayCore
import XCTest

final class OverlayGeometryTests: XCTestCase {
    func testPanelFrameIsCenteredAtTopOfScreen() {
        let screen = OverlayScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 33, width: 1512, height: 868),
            safeAreaTop: 37
        )

        XCTAssertEqual(
            OverlayGeometry.panelFrame(on: screen),
            CGRect(x: 506, y: 770, width: 500, height: 212)
        )
    }

    func testPanelWidthIsClampedOnNarrowScreens() {
        let screen = OverlayScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 320, height: 640),
            visibleFrame: CGRect(x: 0, y: 24, width: 320, height: 616),
            safeAreaTop: 0
        )

        XCTAssertEqual(
            OverlayGeometry.panelFrame(on: screen),
            CGRect(x: 16, y: 428, width: 288, height: 212)
        )
    }

    func testClosedHeightUsesSafeAreaForNotchedDisplays() {
        let screen = OverlayScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 33, width: 1512, height: 868),
            safeAreaTop: 37
        )

        XCTAssertEqual(OverlayGeometry.closedHeight(for: screen), 37)
    }

    func testClosedHeightFallsBackToMenuBarReservation() {
        let screen = OverlayScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 876),
            safeAreaTop: 0
        )

        XCTAssertEqual(OverlayGeometry.closedHeight(for: screen), 24)
    }

    func testCollapsedPanelFrameIsCenteredInMenuBarArea() {
        let screen = OverlayScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 33, width: 1512, height: 868),
            safeAreaTop: 37
        )

        XCTAssertEqual(
            OverlayGeometry.collapsedPanelFrame(on: screen),
            CGRect(x: 666, y: 945, width: 180, height: 37)
        )
    }

}
