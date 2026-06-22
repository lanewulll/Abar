import AbarOverlayCore
import Foundation

@MainActor
final class AbarMaintenanceService {
    private let store: AbarEventStore
    private let projectPath: String
    private let onChanged: @MainActor () -> Void
    private let queue = DispatchQueue(label: "dev.abar.native-overlay.maintenance")
    private var quotaTimer: Timer?
    private var skillsTimer: Timer?
    private var quotaRefreshInFlight = false
    private var skillsRefreshInFlight = false

    init(store: AbarEventStore, projectPath: String, onChanged: @escaping @MainActor () -> Void) {
        self.store = store
        self.projectPath = projectPath
        self.onChanged = onChanged
    }

    func start() {
        refreshQuota()
        rescanSkills()
        quotaTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshQuota() }
        }
        skillsTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rescanSkills() }
        }
    }

    func stop() {
        quotaTimer?.invalidate()
        skillsTimer?.invalidate()
        quotaTimer = nil
        skillsTimer = nil
    }

    func refreshQuota() {
        guard !quotaRefreshInFlight else { return }
        quotaRefreshInFlight = true
        queue.async { [store] in
            let snapshot = AbarQuotaRefresher.refresh()
            do {
                try store.insertQuotaSnapshot(snapshot)
            } catch {
                NSLog("[AbarNativeOverlay] quota refresh failed to write snapshot: %@", String(describing: error))
            }
            DispatchQueue.main.async { [weak self] in
                self?.quotaRefreshInFlight = false
                self?.onChanged()
            }
        }
    }

    func rescanSkills() {
        guard !skillsRefreshInFlight else { return }
        skillsRefreshInFlight = true
        queue.async { [store, projectPath] in
            let result = AbarSkillScanner.scan(projectPath: projectPath)
            do {
                try store.replaceSkills(result.skills, scannedAt: result.scannedAt)
            } catch {
                NSLog("[AbarNativeOverlay] skill scan failed to write skills: %@", String(describing: error))
            }
            if !result.errors.isEmpty {
                NSLog("[AbarNativeOverlay] skill scan completed with errors: %@", result.errors.joined(separator: " | "))
            }
            DispatchQueue.main.async { [weak self] in
                self?.skillsRefreshInFlight = false
                self?.onChanged()
            }
        }
    }
}
