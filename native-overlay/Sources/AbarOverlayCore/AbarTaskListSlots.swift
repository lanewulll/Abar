import Foundation

public struct AbarTaskListSlot: Identifiable, Equatable {
    public var id: Int
    public var task: AbarTaskSummary?

    public var isEmpty: Bool {
        task == nil
    }

    public init(id: Int, task: AbarTaskSummary?) {
        self.id = id
        self.task = task
    }
}

public enum AbarTaskListSlots {
    public static let visibleSlotCount = 4

    public static func make(tasks: [AbarTaskSummary]) -> [AbarTaskListSlot] {
        (0..<visibleSlotCount).map { index in
            AbarTaskListSlot(id: index, task: index < tasks.count ? tasks[index] : nil)
        }
    }
}
