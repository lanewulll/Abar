import AbarOverlayCore
import SwiftUI

struct AbarOverlayView: View {
    @ObservedObject var model: AbarOverlayModel
    @Environment(\.colorScheme) private var colorScheme

    private var palette: AbarOverlayPalette {
        AbarOverlayPalette(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            if model.isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                collapsedContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: AbarOverlayPresentationPolicy.contentAnimationDuration), value: model.isExpanded)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                QuotaZone(kind: .fiveHour, title: "5H", systemImage: "clock", summary: model.snapshot.fiveHour, alignment: .leading)
                    .frame(width: 138, height: 66)
                CodexSourceZone(summary: model.snapshot.codexConnection)
                    .frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66)
                QuotaZone(kind: .weekly, title: "WEEKLY", systemImage: "calendar.badge.clock", summary: model.snapshot.weekly, alignment: .trailing)
                    .frame(width: 138, height: 66)
            }
            .frame(height: 66)

            TaskList(tasks: model.displayedTasks, now: model.clockNow) { task in
                model.activate(task: task)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(width: OverlayGeometry.preferredWidth, height: OverlayGeometry.preferredHeight)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(palette.panelScrim)
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.panelBorder, lineWidth: 1.0)
        )
    }

    private var collapsedContent: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: OverlayGeometry.collapsedWidth, height: 28)
    }

}

private struct AbarOverlayPalette {
    let panelScrim: Color
    let panelBorder: Color
    let primaryText: Color
    let secondaryText: Color
    let subduedText: Color
    let accent: Color
    let progressTrack: Color
    let progressFill: Color
    let runningRow: Color
    let runningMarquee: Color
    let runningMarqueeGlow: Color
    let completedRow: Color
    let jumpIcon: Color
    let jumpHoverBackground: Color

    init(colorScheme: ColorScheme) {
        switch colorScheme {
        case .dark:
            panelScrim = Color(red: 0.05, green: 0.07, blue: 0.07).opacity(0.54)
            panelBorder = Color.white.opacity(0.18)
            primaryText = Color.white.opacity(0.96)
            secondaryText = Color.white.opacity(0.82)
            subduedText = Color.white.opacity(0.70)
            accent = Color(red: 0.32, green: 0.72, blue: 1.00).opacity(0.96)
            progressTrack = Color.white.opacity(0.18)
            progressFill = Color(red: 0.18, green: 0.63, blue: 1.00).opacity(0.95)
            runningRow = Color(red: 0.25, green: 0.73, blue: 0.40).opacity(0.48)
            runningMarquee = Color(red: 0.62, green: 0.98, blue: 0.70).opacity(0.96)
            runningMarqueeGlow = Color(red: 0.35, green: 0.95, blue: 0.48)
            completedRow = Color.white.opacity(0.14)
            jumpIcon = Color.white.opacity(0.88)
            jumpHoverBackground = Color.white.opacity(0.18)
        default:
            panelScrim = Color.white.opacity(0.50)
            panelBorder = Color.black.opacity(0.12)
            primaryText = Color(red: 0.08, green: 0.10, blue: 0.12).opacity(0.95)
            secondaryText = Color(red: 0.16, green: 0.20, blue: 0.25).opacity(0.84)
            subduedText = Color(red: 0.25, green: 0.30, blue: 0.36).opacity(0.76)
            accent = Color(red: 0.05, green: 0.43, blue: 0.92).opacity(0.92)
            progressTrack = Color.black.opacity(0.13)
            progressFill = Color(red: 0.04, green: 0.50, blue: 0.95).opacity(0.92)
            runningRow = Color(red: 0.46, green: 0.84, blue: 0.55).opacity(0.52)
            runningMarquee = Color(red: 0.05, green: 0.56, blue: 0.18).opacity(0.88)
            runningMarqueeGlow = Color(red: 0.12, green: 0.72, blue: 0.28)
            completedRow = Color(red: 0.10, green: 0.13, blue: 0.16).opacity(0.10)
            jumpIcon = Color(red: 0.10, green: 0.13, blue: 0.16).opacity(0.80)
            jumpHoverBackground = Color.black.opacity(0.08)
        }
    }
}

private struct QuotaZone: View {
    let kind: AbarQuotaWindowKind
    let title: String
    let systemImage: String
    let summary: QuotaWindowSummary
    let alignment: HorizontalAlignment
    @Environment(\.colorScheme) private var colorScheme

    private var palette: AbarOverlayPalette {
        AbarOverlayPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            titleRow

            Text(valueText)
                .font(.system(size: 25, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.primaryText)

            ProgressBar(progress: progress)

            if let resetText {
                Text(resetText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.subduedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
    }

    @ViewBuilder
    private var titleRow: some View {
        HStack(spacing: 6) {
            if alignment == .trailing {
                Spacer(minLength: 0)
            }
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.subduedText)
                .lineLimit(1)
            if alignment == .leading {
                Spacer(minLength: 0)
            }
        }
    }

    private var valueText: String {
        summary.remainingPercent.map { "\($0)%" } ?? "n/a"
    }

    private var progress: Double? {
        guard let remainingPercent = summary.remainingPercent else { return nil }
        return min(max(Double(remainingPercent) / 100, 0), 1)
    }

    private var resetText: String? {
        AbarQuotaResetLabel.text(for: kind, resetsAt: summary.resetsAt)
    }

    private var frameAlignment: Alignment {
        alignment == .trailing ? .topTrailing : .topLeading
    }
}

private struct ProgressBar: View {
    let progress: Double?
    @Environment(\.colorScheme) private var colorScheme

    private var palette: AbarOverlayPalette {
        AbarOverlayPalette(colorScheme: colorScheme)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.progressTrack)
                Capsule()
                    .fill(progress == nil ? palette.progressFill.opacity(0.34) : palette.progressFill)
                    .frame(width: proxy.size.width * CGFloat(progress ?? 0))
            }
        }
        .frame(height: 4)
    }
}

private struct CodexSourceZone: View {
    let summary: AbarCodexConnectionSummary
    @Environment(\.colorScheme) private var colorScheme

    private var palette: AbarOverlayPalette {
        AbarOverlayPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 16)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.subduedText)
                .lineLimit(1)
            Text(summary.displayText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 8)
    }

    private var label: String {
        switch summary.mode {
        case .account:
            return "Codex account"
        case .api:
            return "Codex API"
        case .unknown:
            return "Codex source"
        }
    }
}

private struct TaskList: View {
    let tasks: [AbarTaskSummary]
    let now: Date
    let onJump: (AbarTaskSummary) -> Void

    var body: some View {
        VStack(spacing: 5) {
            ForEach(AbarTaskListSlots.make(tasks: tasks)) { slot in
                if let task = slot.task {
                    TaskRow(task: task, now: now, onJump: onJump)
                } else {
                    EmptyTaskSlot()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct EmptyTaskSlot: View {
    var body: some View {
        Color.clear
            .frame(height: 27)
    }
}

private struct TaskRow: View {
    let task: AbarTaskSummary
    let now: Date
    let onJump: (AbarTaskSummary) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var palette: AbarOverlayPalette {
        AbarOverlayPalette(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 8) {
            TaskAvatar(projectName: task.projectName, state: task.state)
            Text(task.projectName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(palette.primaryText)
                .frame(width: 126, alignment: .leading)
            Text(task.promptPreview)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(palette.secondaryText)
            Spacer(minLength: 8)
            trailingControl
        }
        .padding(.horizontal, 6)
        .frame(height: 27)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            if task.state == .running {
                RunningTaskMarqueeBorder(cornerRadius: 9)
            }
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch task.state {
        case .running:
            Text(elapsedText)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.secondaryText)
        case .completed:
            TaskJumpButton {
                onJump(task)
            }
        }
    }

    private var rowBackground: Color {
        switch task.state {
        case .running:
            return palette.runningRow
        case .completed:
            return palette.completedRow
        }
    }

    private var elapsedText: String {
        AbarTaskElapsedText.text(for: task, now: now)
    }
}

private struct RunningTaskMarqueeBorder: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var palette: AbarOverlayPalette {
        AbarOverlayPalette(colorScheme: colorScheme)
    }

    var body: some View {
        if reduceMotion {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(palette.runningMarquee, lineWidth: 1.4)
                .allowsHitTesting(false)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                animatedBorder(at: context.date)
            }
            .allowsHitTesting(false)
        }
    }

    private func animatedBorder(at date: Date) -> some View {
        let period = 1.4
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        let progress = elapsed / period
        let pulse = progress < 0.5 ? progress * 2 : (1 - progress) * 2
        let dashPhase = CGFloat(progress * -32)

        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(palette.runningMarqueeGlow.opacity(0.16 + pulse * 0.18), lineWidth: 3.0)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    palette.runningMarquee,
                    style: StrokeStyle(
                        lineWidth: 1.45,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [13, 8],
                        dashPhase: dashPhase
                    )
                )
        }
    }
}

private struct TaskAvatar: View {
    let projectName: String
    let state: AbarTaskState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(AbarTaskAvatarInitial.initial(for: projectName))
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(foregroundColor)
            .frame(width: 24, height: 24)
            .background(backgroundColor, in: Circle())
    }

    private var backgroundColor: Color {
        switch state {
        case .running:
            return Color(red: 0.62, green: 0.90, blue: 0.66)
        case .completed:
            switch colorScheme {
            case .dark:
                return Color.white.opacity(0.26)
            default:
                return Color(red: 0.72, green: 0.76, blue: 0.78).opacity(0.90)
            }
        }
    }

    private var foregroundColor: Color {
        switch state {
        case .running:
            return Color(red: 0.04, green: 0.34, blue: 0.12)
        case .completed:
            switch colorScheme {
            case .dark:
                return Color.white.opacity(0.82)
            default:
                return Color(red: 0.22, green: 0.25, blue: 0.28)
            }
        }
    }
}

private struct TaskJumpButton: View {
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var palette: AbarOverlayPalette {
        AbarOverlayPalette(colorScheme: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.jumpIcon.opacity(isHovered ? 1.0 : 0.82))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(TaskJumpButtonStyle(isHovered: isHovered, hoverBackground: palette.jumpHoverBackground))
        .onHover { isHovered = $0 }
        .accessibilityLabel("Open Codex task")
    }
}

private struct TaskJumpButtonStyle: ButtonStyle {
    let isHovered: Bool
    let hoverBackground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? hoverBackground : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.68 : 1)
    }
}
