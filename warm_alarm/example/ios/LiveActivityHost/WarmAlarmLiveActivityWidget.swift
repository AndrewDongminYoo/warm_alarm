import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WarmAlarmWidgetBundle: WidgetBundle {
    var body: some Widget {
        WarmAlarmLiveActivityWidget()
    }
}

struct WarmAlarmLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WarmAlarmActivityAttributes.self) { context in
            WarmAlarmLockScreenView(context: context)
                .activityBackgroundTint(.orange.opacity(0.18))
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.status.systemImageName)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.center) {
                    WarmAlarmStatusView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WarmAlarmScheduleView(scheduledAt: context.state.scheduledAt)
                }
            } compactLeading: {
                Image(systemName: context.state.status.systemImageName)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(context.state.accessibilityLabel)
            } compactTrailing: {
                WarmAlarmScheduleView(scheduledAt: context.state.scheduledAt)
            } minimal: {
                Image(systemName: context.state.status.systemImageName)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(context.state.accessibilityLabel)
            }
            .keylineTint(.orange)
        }
    }
}

private struct WarmAlarmLockScreenView: View {
    let context: ActivityViewContext<WarmAlarmActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: context.state.status.systemImageName)
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            WarmAlarmStatusView(context: context)
            Spacer(minLength: 12)
            WarmAlarmScheduleView(scheduledAt: context.state.scheduledAt)
        }
        .padding()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(context.state.accessibilityLabel)
    }
}

private struct WarmAlarmStatusView: View {
    let context: ActivityViewContext<WarmAlarmActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(context.state.title)
                .font(.headline)
                .lineLimit(1)
            Text(context.state.status.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(context.state.accessibilityLabel)
    }
}

private struct WarmAlarmScheduleView: View {
    let scheduledAt: Date?

    var body: some View {
        if let scheduledAt {
            Text(scheduledAt, style: .timer)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .accessibilityLabel(Text("Alarm time, \(scheduledAt.formatted(date: .omitted, time: .shortened))"))
        }
    }
}

private extension WarmAlarmActivityAttributes.Status {
    var displayName: String {
        switch self {
        case .scheduled: "Scheduled"
        case .ringing: "Ringing"
        case .snoozed: "Snoozed"
        }
    }

    var systemImageName: String {
        switch self {
        case .scheduled: "alarm"
        case .ringing: "bell.and.waves.left.and.right"
        case .snoozed: "zzz"
        }
    }
}

private extension WarmAlarmActivityAttributes.ContentState {
    var accessibilityLabel: Text {
        if let scheduledAt {
            return Text(
                "\(title), \(status.displayName), alarm time \(scheduledAt.formatted(date: .omitted, time: .shortened))"
            )
        }
        return Text("\(title), \(status.displayName)")
    }
}
