import AbarOverlayCore
import Foundation

@MainActor
final class AbarOverlayModel: ObservableObject {
    @Published private(set) var snapshot: AbarSnapshot = .empty()
    @Published private(set) var errorMessage: String?
    @Published private(set) var isExpanded = false

    private let reader: AbarDatabaseReader
    private let databasePath: String
    private var timer: Timer?

    init(databasePath: String = AbarOverlayModel.defaultDatabasePath()) {
        self.databasePath = databasePath
        reader = AbarDatabaseReader(databasePath: databasePath)
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        do {
            snapshot = try reader.loadSnapshot()
            errorMessage = nil
        } catch {
            errorMessage = "Waiting for Abar data at \(databasePath): \(error)"
        }
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
    }

    static func defaultDatabasePath() -> String {
        let override = ProcessInfo.processInfo.environment["ABAR_NATIVE_DB_PATH"] ?? ""
        if !override.isEmpty {
            return override
        }

        return (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/abar/abar.sqlite")
    }
}
