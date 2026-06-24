@testable import AbarNativeOverlay
import AbarOverlayCore
import XCTest

final class AbarStatusIconAppearanceTests: XCTestCase {
    func testIdleUsesSystemTemplateCWithoutGlow() {
        let appearance = AbarStatusIconAppearance.resolve(state: .idle, pulsePhase: false)

        XCTAssertEqual(appearance.tone, .system)
        XCTAssertTrue(appearance.isTemplate)
        XCTAssertFalse(appearance.glow)
        XCTAssertEqual(appearance.alpha, 1.0, accuracy: 0.001)
    }

    func testRunningUsesGreenGlowAndPulseAlpha() {
        let dim = AbarStatusIconAppearance.resolve(state: .running, pulsePhase: false)
        let bright = AbarStatusIconAppearance.resolve(state: .running, pulsePhase: true)

        XCTAssertEqual(dim.tone, .green)
        XCTAssertEqual(bright.tone, .green)
        XCTAssertFalse(dim.isTemplate)
        XCTAssertFalse(bright.isTemplate)
        XCTAssertTrue(dim.glow)
        XCTAssertTrue(bright.glow)
        XCTAssertEqual(dim.alpha, 0.70, accuracy: 0.001)
        XCTAssertEqual(bright.alpha, 1.0, accuracy: 0.001)
    }

    func testInterruptedUsesRedStaticC() {
        let appearance = AbarStatusIconAppearance.resolve(state: .interrupted, pulsePhase: true)

        XCTAssertEqual(appearance.tone, .red)
        XCTAssertFalse(appearance.isTemplate)
        XCTAssertFalse(appearance.glow)
        XCTAssertEqual(appearance.alpha, 1.0, accuracy: 0.001)
    }
}
