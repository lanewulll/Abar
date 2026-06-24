import AbarOverlayCore
import XCTest

final class AbarTaskAvatarInitialTests: XCTestCase {
    func testUsesFirstVisibleCharacterFromEnglishProjectName() {
        XCTAssertEqual(AbarTaskAvatarInitial.initial(for: "paper-reader-skill"), "P")
    }

    func testUsesFirstVisibleCharacterFromChineseProjectName() {
        XCTAssertEqual(AbarTaskAvatarInitial.initial(for: " 论文阅读 "), "论")
    }

    func testFallsBackToCWhenProjectNameIsBlank() {
        XCTAssertEqual(AbarTaskAvatarInitial.initial(for: " \n\t "), "C")
    }
}
