import AbarOverlayCore
import XCTest

final class AbarQuotaResetLabelTests: XCTestCase {
    func testFiveHourResetTodayUsesChineseRelativeDay() {
        XCTAssertEqual(
            AbarQuotaResetLabel.text(
                for: .fiveHour,
                resetsAt: Self.date("2026-06-23T10:00:00Z"),
                now: Self.date("2026-06-23T06:00:00Z"),
                calendar: Self.utcCalendar
            ),
            "今日 10:00"
        )
    }

    func testFiveHourResetTomorrowUsesChineseRelativeDay() {
        XCTAssertEqual(
            AbarQuotaResetLabel.text(
                for: .fiveHour,
                resetsAt: Self.date("2026-06-24T12:30:00Z"),
                now: Self.date("2026-06-23T06:00:00Z"),
                calendar: Self.utcCalendar
            ),
            "明日 12:30"
        )
    }

    func testFiveHourResetAfterTomorrowUsesMonthDayTime() {
        XCTAssertEqual(
            AbarQuotaResetLabel.text(
                for: .fiveHour,
                resetsAt: Self.date("2026-06-25T12:30:00Z"),
                now: Self.date("2026-06-23T06:00:00Z"),
                calendar: Self.utcCalendar
            ),
            "6月25日 12:30"
        )
    }

    func testWeeklyAlwaysUsesMonthDayTime() {
        XCTAssertEqual(
            AbarQuotaResetLabel.text(
                for: .weekly,
                resetsAt: Self.date("2026-06-24T12:30:00Z"),
                now: Self.date("2026-06-23T06:00:00Z"),
                calendar: Self.utcCalendar
            ),
            "6月24日 12:30"
        )
    }

    func testNilResetDateReturnsNil() {
        XCTAssertNil(
            AbarQuotaResetLabel.text(
                for: .fiveHour,
                resetsAt: nil,
                now: Self.date("2026-06-23T06:00:00Z"),
                calendar: Self.utcCalendar
            )
        )
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
