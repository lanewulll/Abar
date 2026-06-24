import Foundation

public enum AbarMaintenanceOutputPolicy {
    public static func accepts(status: Int32, stdout: String) -> Bool {
        if status == 0 { return true }
        guard let data = stdout.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
        else { return false }
        return true
    }
}

public enum AbarProductSeverity: String, Sendable {
    case notice
    case warning
    case critical
}

public struct AbarProductStatusPresentation: Equatable, Sendable {
    public var title: String
    public var explanation: String
    public var primaryAction: String
    public var secondaryAction: String?
    public var technicalDetails: String
    public var otherFeaturesAvailable: Bool

    public init(
        title: String,
        explanation: String,
        primaryAction: String,
        secondaryAction: String? = nil,
        technicalDetails: String,
        otherFeaturesAvailable: Bool
    ) {
        self.title = title
        self.explanation = explanation
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.technicalDetails = technicalDetails
        self.otherFeaturesAvailable = otherFeaturesAvailable
    }
}

public enum AbarProductIssue: String, CaseIterable, Sendable {
    case quotaUnavailable
    case codexCLIMissing
    case codexNotLoggedIn
    case hooksMissing
    case hooksInvalid
    case hooksNeedTrust
    case reporterPathInvalid
    case projectMoved
    case serverNotRunning
    case portConflict
    case healthFailed
    case databaseUnavailable
    case unsignedAppBlocked
    case setupIncomplete
    case updateFailed

    public var severity: AbarProductSeverity {
        switch self {
        case .quotaUnavailable, .hooksNeedTrust, .projectMoved, .updateFailed:
            return .warning
        case .unsignedAppBlocked:
            return .notice
        default:
            return .critical
        }
    }

    public var presentation: AbarProductStatusPresentation {
        switch self {
        case .quotaUnavailable:
            return status("额度数据暂时不可用", "任务追踪仍可继续使用；Abar 会保留最近一次可用额度。", "重试额度", "使用缓存数据", "HTTP 状态、wham/usage 响应类别、最近成功刷新时间", true)
        case .codexCLIMissing:
            return status("未找到 Codex", "Abar 需要本机 Codex CLI 才能检查登录和 Hook。", "查看安装说明", "运行诊断", "codex 可执行文件搜索结果与 PATH", false)
        case .codexNotLoggedIn:
            return status("Codex 尚未登录", "本地任务追踪可在 Hook 可用时继续，额度功能需要有效登录。", "重新检查登录", "打开登录命令", "codex login status 的脱敏输出", true)
        case .hooksMissing:
            return status("任务追踪尚未配置", "Codex 还不会把任务状态发送给 Abar。", "修复设置", "预览 Hook 配置", "hooks.json 路径与事件缺失情况", false)
        case .hooksInvalid:
            return status("Hook 配置需要修复", "hooks.json 不是有效 JSON，Abar 不会覆盖它。", "打开配置文件", "复制新配置", "JSON 解析错误与 hooks.json 路径", false)
        case .hooksNeedTrust:
            return status("请确认 Hook 信任", "Abar 无法读取 Codex 的信任结果；请在 /hooks 中确认两个 Abar Hook 已信任。", "复制 /hooks", "重新检查", "Hook 信任只能由 Codex 确认，Abar 状态为 unknown", true)
        case .reporterPathInvalid:
            return status("任务连接路径已失效", "Hook 指向的 Reporter 不存在，通常是安装不完整。", "重新安装 Hook", "运行诊断", "Reporter 绝对路径与文件存在状态", false)
        case .projectMoved:
            return status("旧版 Hook 路径已失效", "源码目录移动后，旧版 Hook 仍指向原位置。", "迁移到稳定 Hook", "查看旧路径", "旧版 Reporter 绝对路径", false)
        case .serverNotRunning:
            return status("Abar 本地服务未运行", "Codex 事件暂时无法进入 Abar。", "启动 Abar", "运行诊断", "127.0.0.1 监听状态与进程信息", false)
        case .portConflict:
            return status("本地端口被其他程序占用", "Abar 无法在配置端口启动事件服务。", "查看占用程序", "复制修复说明", "端口、PID、进程名与 lsof 摘要", false)
        case .healthFailed:
            return status("Abar 连接检查失败", "服务进程存在，但健康接口没有返回正常结果。", "重试", "运行诊断", "health endpoint、HTTP 响应和超时类别", false)
        case .databaseUnavailable:
            return status("本地数据暂时不可用", "Abar 无法读取或写入本地数据库。", "重试", "打开数据位置", "SQLite 路径、权限和错误类别", false)
        case .unsignedAppBlocked:
            return status("macOS 需要确认此应用", "Abar 是本地源码构建，未使用 Developer ID 签名或公证。", "打开安全说明", "重新安装", "Gatekeeper 与签名检查结果", false)
        case .setupIncomplete:
            return status("Abar 设置尚未完成", "应用、Hook 或本地服务至少有一项尚未就绪。", "修复设置", "运行诊断", "安装路径、Hook、服务和数据库综合状态", false)
        case .updateFailed:
            return status("暂时无法检查更新", "Abar 仍可正常使用，稍后可再次连接 GitHub 检查。", "重试更新", "复制更新命令", "GitHub 请求状态、当前提交与错误类别", true)
        }
    }

    private func status(
        _ title: String,
        _ explanation: String,
        _ primary: String,
        _ secondary: String?,
        _ technical: String,
        _ available: Bool
    ) -> AbarProductStatusPresentation {
        AbarProductStatusPresentation(
            title: title,
            explanation: explanation,
            primaryAction: primary,
            secondaryAction: secondary,
            technicalDetails: technical,
            otherFeaturesAvailable: available
        )
    }
}
