import AbarOverlayCore
import XCTest

final class AbarProductStatusTests: XCTestCase {
    func testEveryFailureStatusHasUserCopyActionsAndTechnicalDetails() {
        XCTAssertEqual(AbarProductIssue.allCases.count, 15)

        for issue in AbarProductIssue.allCases {
            let presentation = issue.presentation
            XCTAssertFalse(presentation.title.isEmpty, "\(issue) 缺少标题")
            XCTAssertFalse(presentation.explanation.isEmpty, "\(issue) 缺少解释")
            XCTAssertFalse(presentation.primaryAction.isEmpty, "\(issue) 缺少主操作")
            XCTAssertFalse(presentation.technicalDetails.isEmpty, "\(issue) 缺少技术详情")
        }
    }

    func testQuotaFailureKeepsLocalTrackingAvailable() {
        let status = AbarProductIssue.quotaUnavailable.presentation
        XCTAssertTrue(status.otherFeaturesAvailable)
        XCTAssertEqual(status.primaryAction, "重试额度")
        XCTAssertEqual(status.secondaryAction, "使用缓存数据")
    }

    func testBrokenSetupOffersRepairAndDoctor() {
        let status = AbarProductIssue.setupIncomplete.presentation
        XCTAssertFalse(status.otherFeaturesAvailable)
        XCTAssertEqual(status.primaryAction, "修复设置")
        XCTAssertEqual(status.secondaryAction, "运行诊断")
    }

    func testDiagnosticJSONIsAcceptedEvenWhenDoctorReturnsNonzero() {
        XCTAssertTrue(AbarMaintenanceOutputPolicy.accepts(status: 2, stdout: #"{"overall":"broken"}"#))
        XCTAssertFalse(AbarMaintenanceOutputPolicy.accepts(status: 2, stdout: "plain failure"))
    }
}
