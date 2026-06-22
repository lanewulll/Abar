import AbarOverlayCore
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: OverlayPanelController?
    private var eventServer: AbarLocalEventServer?
    private var maintenanceService: AbarMaintenanceService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = OverlayPanelController()
        overlayController = controller
        startLocalEventServer(controller: controller)
        controller.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventServer?.stop()
        maintenanceService?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func startLocalEventServer(controller: OverlayPanelController) {
        let databasePath = AbarOverlayModel.defaultDatabasePath()
        let store = AbarEventStore(databasePath: databasePath)
        do {
            try store.initialize(defaultPort: 3987)
        } catch {
            NSLog("[AbarNativeOverlay] failed to initialize event store: %@", String(describing: error))
        }

        let server = AbarLocalEventServer(port: 3987, store: store) {
            controller.refresh()
        }
        eventServer = server
        server.start()

        let projectPath = (try? store.configValue(key: "project_path")) ?? FileManager.default.currentDirectoryPath
        let maintenanceService = AbarMaintenanceService(store: store, projectPath: projectPath) {
            controller.refresh()
        }
        self.maintenanceService = maintenanceService
        maintenanceService.start()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
