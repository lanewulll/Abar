import AbarOverlayCore
import AppKit

@MainActor
final class TaskNavigator {
    private let openDeepLink: (URL) -> Bool
    private let activateBundle: (String) -> Bool

    init(workspace: NSWorkspace = .shared) {
        openDeepLink = { url in
            workspace.open(url)
        }
        activateBundle = { bundleIdentifier in
            Self.activate(bundleIdentifier: bundleIdentifier, workspace: workspace)
        }
    }

    init(
        openDeepLink: @escaping (URL) -> Bool,
        activateBundle: @escaping (String) -> Bool
    ) {
        self.openDeepLink = openDeepLink
        self.activateBundle = activateBundle
    }

    func activate(task: AbarTaskSummary) {
        let plan = CodexTaskNavigationPlan.make(for: task)
        if let deepLinkURL = plan.deepLinkURL,
           openDeepLink(deepLinkURL) {
            _ = activateBundle(plan.fallbackBundleIdentifier)
            return
        }
        _ = activateBundle(plan.fallbackBundleIdentifier)
    }

    @discardableResult
    private static func activate(bundleIdentifier: String, workspace: NSWorkspace) -> Bool {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            app.unhide()
            let activated = app.activate(options: [.activateAllWindows])
            let scriptActivated = activateWithAppleScript(bundleIdentifier: bundleIdentifier)
            return activated || scriptActivated
        }

        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration) { app, _ in
            app?.activate(options: [.activateAllWindows])
        }
        return true
    }

    @discardableResult
    private static func activateWithAppleScript(bundleIdentifier: String) -> Bool {
        let activateSource = """
        tell application id "\(bundleIdentifier)" to activate
        """
        var activateError: NSDictionary?
        NSAppleScript(source: activateSource)?.executeAndReturnError(&activateError)

        let frontmostSource = """
        tell application "System Events"
          set frontmost of first process whose bundle identifier is "\(bundleIdentifier)" to true
        end tell
        """
        var frontmostError: NSDictionary?
        NSAppleScript(source: frontmostSource)?.executeAndReturnError(&frontmostError)

        return activateError == nil
    }
}
