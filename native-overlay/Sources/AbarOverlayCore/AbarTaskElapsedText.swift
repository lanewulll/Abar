import Foundation

public enum AbarTaskElapsedText {
    public static func text(for task: AbarTaskSummary, now: Date = Date()) -> String {
        let seconds: Int
        switch task.state {
        case .running:
            seconds = max(0, Int(now.timeIntervalSince(task.startedAt)))
        case .completed:
            seconds = max(0, task.durationSeconds)
        }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }
}
