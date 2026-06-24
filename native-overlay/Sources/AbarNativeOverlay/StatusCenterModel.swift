import AbarOverlayCore
import AppKit
import Foundation

@MainActor
final class StatusCenterModel: ObservableObject {
    @Published var issues: [AbarProductIssue] = [.setupIncomplete]
    @Published var diagnosticText = "正在检查 Abar 状态…"
    @Published var isRefreshing = false
    @Published var updateMessage = "尚未检查更新"
    @Published var lastQuotaSnapshot = "尚无额度快照"
    @Published var automaticUpdateChecks: Bool {
        didSet { UserDefaults.standard.set(automaticUpdateChecks, forKey: Self.autoUpdateKey) }
    }

    let databasePath = AbarOverlayModel.defaultDatabasePath()
    let hooksPath = (AbarRuntimeConfiguration.codexHome() as NSString).appendingPathComponent("hooks.json")
    let logPath = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/Abar")
    let cachePath = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches/dev.abar.native-overlay")
    private let onRefreshOverlay: () -> Void

    private static let autoUpdateKey = "AbarAutomaticUpdateChecks"
    private static let lastUpdateCheckKey = "AbarLastUpdateCheck"

    init(onRefreshOverlay: @escaping () -> Void) {
        self.onRefreshOverlay = onRefreshOverlay
        if UserDefaults.standard.object(forKey: Self.autoUpdateKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.autoUpdateKey)
        }
        automaticUpdateChecks = UserDefaults.standard.bool(forKey: Self.autoUpdateKey)
    }

    func start() {
        refresh()
        if automaticUpdateChecks, shouldRunDailyUpdateCheck {
            checkForUpdates()
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        runMaintenance(["diagnostic", "--json"]) { [weak self] result in
            guard let self else { return }
            self.isRefreshing = false
            switch result {
            case let .success(output):
                self.diagnosticText = output
                self.issues = Self.deriveIssues(from: output)
                self.lastQuotaSnapshot = Self.quotaSnapshotText(from: output)
            case let .failure(error):
                self.diagnosticText = "诊断执行失败：\(error.localizedDescription)"
                self.issues = [.setupIncomplete]
            }
        }
    }

    func checkForUpdates() {
        updateMessage = "正在连接 GitHub 检查更新…"
        runMaintenance(["update", "check", "--json"]) { [weak self] result in
            guard let self else { return }
            UserDefaults.standard.set(Date(), forKey: Self.lastUpdateCheckKey)
            switch result {
            case let .success(output):
                guard let data = output.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = json["status"] as? String
                else {
                    self.updateMessage = "更新响应无法解析"
                    self.appendIssue(.updateFailed)
                    return
                }
                if status == "available" {
                    let latest = (json["latestCommit"] as? String)?.prefix(8) ?? "未知"
                    self.updateMessage = "发现更新：main \(latest)"
                } else if status == "current" {
                    self.updateMessage = "当前已是最新版本"
                } else {
                    self.updateMessage = "无法判断更新状态"
                }
                self.issues.removeAll { $0 == .updateFailed }
            case let .failure(error):
                self.updateMessage = "检查失败：\(error.localizedDescription)"
                self.appendIssue(.updateFailed)
            }
        }
    }

    func performPrimaryAction(for issue: AbarProductIssue) {
        switch issue {
        case .quotaUnavailable, .healthFailed, .databaseUnavailable, .updateFailed:
            issue == .updateFailed ? checkForUpdates() : refresh()
            onRefreshOverlay()
        case .hooksMissing, .reporterPathInvalid, .projectMoved, .setupIncomplete:
            confirmAndInstallHooks()
        case .hooksInvalid:
            NSWorkspace.shared.open(URL(fileURLWithPath: hooksPath))
        case .hooksNeedTrust:
            copy("/hooks")
            activateCodex()
        case .codexCLIMissing:
            NSWorkspace.shared.open(URL(string: "https://developers.openai.com/codex/cli/")!)
        case .codexNotLoggedIn:
            copy("codex login")
            showMessage("登录命令已复制", detail: "请在终端运行 codex login，并在浏览器中完成人工登录。")
        case .serverNotRunning:
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Applications/Abar.app")),
                configuration: .init()
            )
        case .portConflict:
            copy("lsof -nP -iTCP:3987 -sTCP:LISTEN")
            showMessage("端口检查命令已复制", detail: "在终端运行后确认占用进程，再决定退出它或为 Abar 与 Hook 同时修改端口。")
        case .unsignedAppBlocked:
            openPrivacyREADME()
        }
    }

    func performSecondaryAction(for issue: AbarProductIssue) {
        switch issue {
        case .quotaUnavailable:
            showMessage("使用缓存数据", detail: "Abar 会继续显示数据库中最近一次成功额度；任务追踪不受影响。")
        case .hooksMissing, .projectMoved:
            previewHooks()
        case .hooksInvalid:
            previewHooks(copyOnly: true)
        case .hooksNeedTrust:
            refresh()
        case .codexNotLoggedIn:
            copy("codex login")
            showMessage("登录命令已复制", detail: "请在终端运行，并在浏览器中完成人工登录。")
        case .codexCLIMissing, .reporterPathInvalid, .serverNotRunning, .healthFailed, .databaseUnavailable, .setupIncomplete:
            refresh()
        case .portConflict:
            copy("lsof -nP -iTCP:3987 -sTCP:LISTEN")
        case .unsignedAppBlocked:
            copy("npm run setup")
        case .updateFailed:
            copyUpdateCommand()
        }
    }

    private func previewHooks(copyOnly: Bool = false) {
        runMaintenance(["hooks", "preview"]) { [weak self] result in
            switch result {
            case let .success(output):
                self?.copy(output)
                if !copyOnly {
                    self?.showMessage("Hook 配置预览已复制", detail: "内容尚未写入 hooks.json。确认后可点击“修复设置”执行备份与安全合并。")
                }
            case let .failure(error):
                self?.showMessage("无法生成 Hook 预览", detail: error.localizedDescription)
            }
        }
    }

    func copyDiagnosticReport() {
        copy(diagnosticText)
    }

    func copyUpdateCommand() {
        copy("git pull --ff-only && npm run setup && npm run hooks:preview && npm run doctor")
    }

    func openPrivacyREADME() {
        NSWorkspace.shared.open(URL(string: "https://github.com/lanewulll/Abar#数据与隐私")!)
    }

    func revealData() {
        let directory = (databasePath as NSString).deletingLastPathComponent
        NSWorkspace.shared.open(URL(fileURLWithPath: directory))
    }

    func deleteLocalData() {
        let alert = NSAlert()
        alert.messageText = "删除 Abar 本地数据？"
        alert.informativeText = "将删除任务、额度和 Skill 快照。Hook 和应用不会被删除；完成后请重新启动 Abar。"
        alert.addButton(withTitle: "删除数据")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for suffix in ["", "-wal", "-shm", ".privacy-backup"] {
            try? FileManager.default.removeItem(atPath: databasePath + suffix)
        }
        diagnosticText = "本地数据已删除。请重新启动 Abar 以创建空数据库。"
        issues = [.databaseUnavailable]
    }

    func requestUninstall(mode: String) {
        runMaintenance(["uninstall", mode, "--dry-run"]) { [weak self] preview in
            guard let self, case let .success(text) = preview else { return }
            let alert = NSAlert()
            alert.messageText = mode == "full" ? "完整卸载 Abar？" : "仅移除 Abar 应用？"
            alert.informativeText = text
            alert.addButton(withTitle: "确认执行")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            self.runMaintenance(["uninstall", mode, "--yes"]) { result in
                switch result {
                case .success:
                    NSApplication.shared.terminate(nil)
                case let .failure(error):
                    self.showMessage("卸载未完成", detail: error.localizedDescription)
                }
            }
        }
    }

    private var shouldRunDailyUpdateCheck: Bool {
        guard let last = UserDefaults.standard.object(forKey: Self.lastUpdateCheckKey) as? Date else { return true }
        return Date().timeIntervalSince(last) >= 86_400
    }

    private func confirmAndInstallHooks() {
        let alert = NSAlert()
        alert.messageText = "安全合并 Abar Hook？"
        alert.informativeText = "Abar 会先备份现有 hooks.json，再只替换 Abar 自己的条目并校验 JSON。完成后仍需你在 Codex 中运行 /hooks 并信任。"
        alert.addButton(withTitle: "备份并合并")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runMaintenance(["hooks", "install"]) { [weak self] result in
            switch result {
            case let .success(output):
                self?.showMessage("Hook 已合并", detail: output)
                self?.refresh()
            case let .failure(error):
                self?.showMessage("Hook 未修改", detail: error.localizedDescription)
            }
        }
    }

    private func runMaintenance(
        _ arguments: [String],
        completion: @escaping @MainActor @Sendable (Result<String, Error>) -> Void
    ) {
        guard let script = maintenanceScriptPath() else {
            completion(.failure(NSError(domain: "Abar", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到维护工具"])))
            return
        }
        guard let nodePath = AbarRuntimeConfiguration.nodeExecutable() else {
            completion(.failure(NSError(domain: "Abar", code: 2, userInfo: [NSLocalizedDescriptionKey: "未找到 Node.js；请安装 Node.js 20 或更高版本"])))
            return
        }
        var environment = ProcessInfo.processInfo.environment
        if let commit = Bundle.main.object(forInfoDictionaryKey: "AbarGitCommit") as? String {
            environment["ABAR_CURRENT_COMMIT"] = commit
        }
        environment["ABAR_INSTALL_DIR"] = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        let processEnvironment = environment
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: nodePath)
            process.arguments = [script.path] + arguments
            process.environment = processEnvironment
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
                process.waitUntilExit()
                let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let errorOutput = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                DispatchQueue.main.async {
                    if AbarMaintenanceOutputPolicy.accepts(status: process.terminationStatus, stdout: output) {
                        completion(.success(output.trimmingCharacters(in: .whitespacesAndNewlines)))
                    } else {
                        completion(.failure(NSError(
                            domain: "AbarMaintenance",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: errorOutput.isEmpty ? output : errorOutput]
                        )))
                    }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func maintenanceScriptPath() -> URL? {
        if let bundled = Bundle.main.url(
            forResource: "abar-maintenance",
            withExtension: "js",
            subdirectory: "maintenance"
        ) {
            return bundled
        }
        if let source = Bundle.main.object(forInfoDictionaryKey: "AbarSourcePath") as? String {
            return URL(fileURLWithPath: source).appendingPathComponent("scripts/abar-maintenance.js")
        }
        return nil
    }

    private static func deriveIssues(from output: String) -> [AbarProductIssue] {
        guard let data = output.data(using: .utf8),
              let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [.setupIncomplete] }
        var result: [AbarProductIssue] = []
        let codex = report["codexCLI"] as? [String: Any] ?? [:]
        if codex["installed"] as? Bool != true { result.append(.codexCLIMissing) }
        let login = report["codexLogin"] as? [String: Any] ?? [:]
        if login["loggedIn"] as? Bool != true { result.append(.codexNotLoggedIn) }
        let hooks = report["hooks"] as? [String: Any] ?? [:]
        if hooks["legacyConfigured"] as? Bool == true {
            result.append(.projectMoved)
        } else if hooks["exists"] as? Bool != true { result.append(.hooksMissing) }
        else if hooks["valid"] as? Bool != true { result.append(.hooksInvalid) }
        else if hooks["configured"] as? Bool != true { result.append(.hooksMissing) }
        else if hooks["reporterPathValid"] as? Bool != true { result.append(.reporterPathInvalid) }
        else { result.append(.hooksNeedTrust) }
        let server = report["localServer"] as? [String: Any] ?? [:]
        if server["healthy"] as? Bool != true {
            if server["portInUse"] as? Bool != true {
                result.append(.serverNotRunning)
            } else if (server["listener"] as? String)?.contains("AbarNativ") == true {
                result.append(.healthFailed)
            } else {
                result.append(.portConflict)
            }
        }
        let database = report["database"] as? [String: Any] ?? [:]
        if database["exists"] as? Bool == true, database["readable"] as? Bool != true {
            result.append(.databaseUnavailable)
        }
        if let quota = report["quotaStatus"] as? String,
           ["cached", "failed", "unavailable", "unavailable-file-auth"].contains(quota) {
            result.append(.quotaUnavailable)
        }
        if report["overall"] as? String == "broken", result.isEmpty {
            result.append(.setupIncomplete)
        }
        return result
    }

    private static func quotaSnapshotText(from output: String) -> String {
        guard let data = output.data(using: .utf8),
              let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let database = report["database"] as? [String: Any],
              let value = database["lastQuotaSnapshot"] as? String,
              !value.isEmpty
        else { return "尚无额度快照" }
        return value
    }

    private func appendIssue(_ issue: AbarProductIssue) {
        if !issues.contains(issue) { issues.append(issue) }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func activateCodex() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first {
            app.activate(options: [.activateAllWindows])
        }
    }

    private func showMessage(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

}
