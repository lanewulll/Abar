import AbarOverlayCore
import SwiftUI

struct StatusCenterView: View {
    @ObservedObject var model: StatusCenterModel
    @State private var selection = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $selection) {
                Text("状态").tag(0)
                Text("隐私与本地数据").tag(1)
                Text("诊断与关于").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Divider()
            Group {
                switch selection {
                case 1: privacyPage
                case 2: diagnosticsPage
                default: statusPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.start() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Abar 状态中心")
                    .font(.system(size: 24, weight: .bold))
                Text("查看连接、隐私、本地数据和修复建议")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.refresh()
            } label: {
                Label(model.isRefreshing ? "检查中…" : "重新检查", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshing)
        }
        .padding(24)
    }

    private var statusPage: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if model.issues.isEmpty {
                    StatusCard(
                        title: "Abar 已准备就绪",
                        explanation: "Codex、本地任务追踪和数据库均可用。",
                        systemImage: "checkmark.circle.fill",
                        color: .green
                    )
                    StatusCard(
                        title: "隐私数据保存在本机",
                        explanation: "任务短标题和运行元数据最多保留滚动 24 小时。",
                        systemImage: "lock.fill",
                        color: .green
                    )
                } else {
                    ForEach(model.issues, id: \.self) { issue in
                        IssueCard(
                            issue: issue,
                            diagnosticText: model.diagnosticText,
                            primaryAction: { model.performPrimaryAction(for: issue) },
                            secondaryAction: { model.performSecondaryAction(for: issue) }
                        )
                    }
                }
            }
            .padding(24)
        }
    }

    private var privacyPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatusCard(
                    title: "数据仅保存在本机",
                    explanation: "Abar 保存任务短标题、项目路径、会话标识、Hook 事件类型、Skill 索引和额度快照；不保存完整 prompt、transcript、令牌、Cookie、Authorization Header、API Key 或密码。",
                    systemImage: "externaldrive.fill.badge.checkmark",
                    color: .green
                )
                pathSection("本地数据库", model.databasePath)
                pathSection("日志目录", model.logPath)
                pathSection("缓存目录", model.cachePath)
                pathSection("Codex Hook 配置", model.hooksPath)
                pathSection("最后额度快照", model.lastQuotaSnapshot)
                Text("记录使用滚动 24 小时保留策略。额度查询会直接请求 ChatGPT 内部 wham/usage 接口；更新检查每天访问一次 GitHub，不发送遥测。")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("在 Finder 中打开数据位置") { model.revealData() }
                    Button("复制诊断报告") { model.copyDiagnosticReport() }
                    Button("打开 README 隐私说明") { model.openPrivacyREADME() }
                    Spacer()
                    Button("删除本地数据", role: .destructive) { model.deleteLocalData() }
                }
                Divider()
                Text("卸载")
                    .font(.headline)
                HStack {
                    Button("仅移除应用…") { model.requestUninstall(mode: "app") }
                    Button("完整卸载…", role: .destructive) { model.requestUninstall(mode: "full") }
                }
            }
            .padding(24)
        }
    }

    private var diagnosticsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Toggle("每天自动检查 GitHub 更新", isOn: $model.automaticUpdateChecks)
                Spacer()
                Button("检查更新") { model.checkForUpdates() }
                Button("复制更新命令") { model.copyUpdateCommand() }
            }
            Text(model.updateMessage)
                .foregroundStyle(.secondary)
            Text("脱敏诊断报告")
                .font(.headline)
            ScrollView {
                Text(model.diagnosticText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            HStack {
                Button("运行诊断") { model.refresh() }
                Button("复制诊断报告") { model.copyDiagnosticReport() }
                Spacer()
                Text("Abar \(appVersion)")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    private func pathSection(_ title: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatusCard: View {
    let title: String
    let explanation: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(explanation).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct IssueCard: View {
    let issue: AbarProductIssue
    let diagnosticText: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void
    @State private var showDetails = false

    var body: some View {
        let presentation = issue.presentation
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: issue.severity == .critical ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundStyle(issue.severity == .critical ? .red : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title).font(.headline)
                    Text(presentation.explanation).foregroundStyle(.secondary)
                    Text(presentation.otherFeaturesAvailable ? "其他本地功能仍可继续使用。" : "完成修复前，相关功能不可用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack {
                Button(presentation.primaryAction, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                if let secondary = presentation.secondaryAction {
                    Button(secondary, action: secondaryAction)
                }
                Button(showDetails ? "隐藏技术详情" : "技术详情") { showDetails.toggle() }
                    .buttonStyle(.link)
            }
            if showDetails {
                Text("\(presentation.technicalDetails)\n\n当前脱敏诊断：\n\(diagnosticText)")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
