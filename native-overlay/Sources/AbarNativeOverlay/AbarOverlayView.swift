import AbarOverlayCore
import SwiftUI

struct AbarOverlayView: View {
    @ObservedObject var model: AbarOverlayModel

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
        .animation(.easeOut(duration: 0.16), value: model.isExpanded)
    }

    private var expandedContent: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                }
                .frame(height: 22)

                HStack(spacing: 10) {
                    MetricPill(title: "5h", value: percentText(model.snapshot.fiveHour.remainingPercent))
                    MetricPill(title: "Weekly", value: percentText(model.snapshot.weekly.remainingPercent))
                    MetricPill(title: "Skills", value: "\(model.snapshot.skillsCount)")
                    MetricPill(title: "Events", value: "\(model.snapshot.eventsCount)")
                }

                TaskList(tasks: model.displayedTasks) { task in
                    model.activate(task: task)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 14)

            HStack(spacing: 8) {
                Button("Refresh") {
                    model.refresh()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 10)
            .padding(.trailing, 18)
        }
        .frame(width: OverlayGeometry.preferredWidth, height: OverlayGeometry.preferredHeight)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(borderColor.opacity(0.86), lineWidth: 1.4)
        )
        .shadow(color: borderColor.opacity(0.22), radius: 20, x: 0, y: 8)
        .shadow(color: .black.opacity(0.16), radius: 28, x: 0, y: 14)
    }

    private var collapsedContent: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: OverlayGeometry.collapsedWidth, height: 28)
    }

    private var borderColor: Color {
        switch model.displayedActivityState {
        case .idle:
            return Color(red: 0.59, green: 0.88, blue: 0.68)
        case .working:
            return Color(red: 0.96, green: 0.79, blue: 0.36)
        }
    }

    private func percentText(_ value: Int?) -> String {
        value.map { "\($0)%" } ?? "n/a"
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct TaskList: View {
    let tasks: [AbarTaskSummary]
    let onJump: (AbarTaskSummary) -> Void

    var body: some View {
        VStack(spacing: 6) {
            if tasks.isEmpty {
                EmptyTaskRow()
            } else {
                ForEach(tasks.prefix(4)) { task in
                    TaskRow(task: task, onJump: onJump)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct EmptyTaskRow: View {
    var body: some View {
        HStack {
            Text("Idle")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("No active task")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct TaskRow: View {
    let task: AbarTaskSummary
    let onJump: (AbarTaskSummary) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(task.projectName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .frame(width: 116, alignment: .leading)
            Text(task.promptPreview)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            trailingControl
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch task.state {
        case .running:
            Text(elapsedText)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .completed:
            Button {
                onJump(task)
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .accessibilityLabel("Open task")
        }
    }

    private var rowBackground: Color {
        switch task.state {
        case .running:
            return Color(red: 1.00, green: 0.92, blue: 0.65).opacity(0.32)
        case .completed:
            return Color(red: 0.67, green: 0.92, blue: 0.73).opacity(0.34)
        }
    }

    private var elapsedText: String {
        let seconds = max(0, task.durationSeconds)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }
}
