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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                statusDot(size: 11)
                Text("Abar Native Overlay")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
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

            HStack(spacing: 10) {
                MetricPill(title: "5h", value: percentText(model.snapshot.fiveHour.usedPercent))
                MetricPill(title: "Weekly", value: percentText(model.snapshot.weekly.usedPercent))
                MetricPill(title: "Skills", value: "\(model.snapshot.skillsCount)")
                MetricPill(title: "Events", value: "\(model.snapshot.eventsCount)")
            }

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(18)
        .frame(width: 500, height: 172)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: 14)
    }

    private var collapsedContent: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 4)
            statusDot(size: 10)
        }
        .frame(width: 72, height: 28)
    }

    private func statusDot(size: CGFloat) -> some View {
        Circle()
            .fill(Color(red: 0.10, green: 0.62, blue: 0.50))
            .frame(width: size, height: size)
            .shadow(color: Color(red: 0.10, green: 0.62, blue: 0.50).opacity(0.35), radius: 6)
    }

    private var statusText: String {
        if let error = model.errorMessage {
            return error
        }

        let latest = model.snapshot.recentEvents.first
        let latestLabel = latest.map { event in
            [event.eventType, event.toolName, event.status]
                .compactMap { $0 }
                .joined(separator: " · ")
        } ?? "No recent activity"
        let project = model.snapshot.projectPath.map(compactPath) ?? "No project"
        return "\(project) · \(latestLabel)"
    }

    private func percentText(_ value: Int?) -> String {
        value.map { "\($0)%" } ?? "n/a"
    }

    private func compactPath(_ value: String) -> String {
        let parts = value.split(separator: "/")
        guard parts.count > 2 else { return value }
        return ".../" + parts.suffix(2).joined(separator: "/")
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
                .font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
