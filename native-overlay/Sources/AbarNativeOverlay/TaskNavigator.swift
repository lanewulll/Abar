import AbarOverlayCore
import AppKit

@MainActor
final class TaskNavigator {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func activate(task: AbarTaskSummary) {
        for bundleIdentifier in preferredBundleIdentifiers(for: task) {
            if activate(bundleIdentifier: bundleIdentifier) {
                return
            }
        }
    }

    private func preferredBundleIdentifiers(for task: AbarTaskSummary) -> [String] {
        if task.id.hasPrefix("chat-conversation:") || task.projectName == "ChatGPT" {
            return ["com.openai.chat", "com.openai.codex"]
        }

        if let frontmost = workspace.frontmostApplication?.bundleIdentifier,
           ["com.openai.chat", "com.openai.codex"].contains(frontmost) {
            return [frontmost] + ["com.openai.chat", "com.openai.codex"].filter { $0 != frontmost }
        }

        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.chat").isEmpty {
            return ["com.openai.chat", "com.openai.codex"]
        }

        return ["com.openai.codex", "com.openai.chat"]
    }

    @discardableResult
    private func activate(bundleIdentifier: String) -> Bool {
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
    private func activateWithAppleScript(bundleIdentifier: String) -> Bool {
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
