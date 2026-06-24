@testable import AbarNativeOverlay
import XCTest

final class StatusItemMenuDefinitionTests: XCTestCase {
    func testRightClickMenuContainsRefreshAndQuit() {
        XCTAssertEqual(StatusItemMenuDefinition.itemTitles, ["Refresh", "Quit Abar"])
    }
}
