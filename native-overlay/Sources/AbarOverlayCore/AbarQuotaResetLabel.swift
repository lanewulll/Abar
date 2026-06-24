import Foundation

public enum AbarQuotaWindowKind: Equatable {
    case fiveHour
    case weekly
}

public enum AbarQuotaResetLabel {
    public static func text(
        for kind: AbarQuotaWindowKind,
        resetsAt: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        guard let resetsAt else { return nil }
        switch kind {
        case .fiveHour:
            if calendar.isDate(resetsAt, inSameDayAs: now) {
                return "今日 \(timeText(resetsAt, calendar: calendar))"
            }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
               calendar.isDate(resetsAt, inSameDayAs: tomorrow) {
                return "明日 \(timeText(resetsAt, calendar: calendar))"
            }
            return monthDayTimeText(resetsAt, calendar: calendar)
        case .weekly:
            return monthDayTimeText(resetsAt, calendar: calendar)
        }
    }

    private static func monthDayTimeText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)月\(components.day ?? 0)日 \(timeText(date, calendar: calendar))"
    }

    private static func timeText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
