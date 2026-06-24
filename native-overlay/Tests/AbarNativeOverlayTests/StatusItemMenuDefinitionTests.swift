@testable import AbarNativeOverlay
import XCTest

final class StatusItemMenuDefinitionTests: XCTestCase {
    func testRightClickMenuContainsStatusCenterRefreshAndQuit() {
        XCTAssertEqual(StatusItemMenuDefinition.itemTitles, ["打开状态中心…", "刷新", "退出 Abar"])
    }
}
